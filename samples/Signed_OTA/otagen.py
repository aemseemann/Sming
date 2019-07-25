#!/usr/bin/env python2

import argparse
import sys, os
import struct
# image signing via libsodium
import nacl.bindings
import nacl.encoding
import nacl.signing

def parse_arguments():
    parser = argparse.ArgumentParser(description="Generate OTA update image")
    parser.add_argument('--genkey', dest='genkey', action='store_true', default=False, help='Generate signing key')
    parser.add_argument('--keyfile', dest='keyfile', help='Path to signing key file (output if \'--genkey\' is given, otherwise input)')
    parser.add_argument('--pubkey-header', dest='pubkey_header', default='', help='Generate header file with verification key (public key)')
    parser.add_argument('-o', '--out', dest='out', default='', help='Path to output file')
    parser.add_argument('rom_images', nargs='*', help='ROM image files with load address, i. e. sequence of address=path/to/image')
    return parser.parse_args()

def parse_address(string):
    try:
        if string.startswith('0x') or string.startswith('0X'):
            return int(string, 16)
        else:
            return int(string, 10)
    except:
        sys.stderr.write(string + ' is not a valid start address\n')
        raise

def write_pubkey_header(pk, filepath):
    with open(filepath, 'w') as header:
        header.write('''\
#ifndef OTA_VERIFICATION_KEY_H
#define OTA_VERIFICATION_KEY_H

#ifdef __cplusplus
extern "C" {
#endif

static const uint8_t OTA_VerificationKey[''' + str(len(pk)) + '''] = {
    ''' + ', '.join('0x%02X' % ord(b) for b in pk) + '''
};
#ifdef __cplusplus
}
#endif
#endif // OTA_VERIFICATION_KEY_H''')        
    print("Verification key written to C header file '%s'\n" % filepath)
    
def load_rom_images(address_file_pairs):
    images = []
    for pair in address_file_pairs:
        [address, filepath] = pair.split('=', 1)
        address = parse_address(address)
        try:
            print('Read image file "' + filepath + '"...')
            with open(filepath, 'rb') as f:
                image_content = f.read()
        except:
            sys.stderr.write('Failed to read "' + filepath + '"\n')
            raise
        
        pad = (len(image_content) + 3) & 0x3
        if pad > 0:
            image_content += bytes(pad)
        images.append((address, image_content))
    
    return images
    
def make_ota_image(images, sk, pk = None):
    magic = 0xf01af02a
    ota = struct.pack('II', magic, len(images))
    for address, content in images:
        ota += struct.pack('II', address, len(content))
        ota += content;
    
    sig_state = nacl.bindings.crypto_sign_ed25519ph_state()
    nacl.bindings.crypto_sign_ed25519ph_update(sig_state, ota)
    signature = nacl.bindings.crypto_sign_ed25519ph_final_create(sig_state, sk)
    print("OTA signature (EdDSA25519ph): " + signature.encode('Hex'))
    
    if pk is not None:
        # test signature verification
        print("Verification key: " + pk.encode('Hex'))
        verify_state = nacl.bindings.crypto_sign_ed25519ph_state()
        nacl.bindings.crypto_sign_ed25519ph_update(verify_state, ota)
        nacl.bindings.crypto_sign_ed25519ph_final_verify(verify_state, signature, pk)
    
    ota += signature
    
    return ota

    
def main():
    args = parse_arguments()
    
    if args.genkey:
        print('Generate signing key...')
        sk_seed = nacl.bindings.randombytes(nacl.bindings.crypto_sign_SEEDBYTES)
        
        if args.keyfile:                
            with open(args.keyfile, 'wb') as privkeyfile:
                privkeyfile.write(sk_seed.encode('Hex'))
            print("Private signing key written to '%s'." % args.keyfile)
        else:
            sys.stderr.write("Warning: Not output file for generated key is given ('--keyfile'). Generated key will be lost.")
    elif args.keyfile:
        print("Read signing key from '%s'" % args.keyfile)
        with open(args.keyfile, 'r') as keyfile:
            sk_seed = keyfile.read().decode('Hex')
    
    else:
        sys.exit("Neither '--genkey' nor '--keyfile' is given. No signing key available.");
    
    (pk, sk) = nacl.bindings.crypto_sign_seed_keypair(sk_seed)
        
    if args.pubkey_header:
        write_pubkey_header(pk, args.pubkey_header)
    
    if args.out:
        if not args.rom_images:
            sys.stderr.write('Warning: no Rom images given. creating empty OTA file')
        
        images = load_rom_images(args.rom_images)
        ota = make_ota_image(images, sk, pk)

        try:
            print('Write OTA update file to "' + args.out + '"')
            with open(args.out, 'wb') as f:
                f.write(ota)
        except:
            sys.stderr.write('Failed to write to "' + args.out + '"\n')
              
    else:
        if len(args.rom_images) > 0:
            sys.stderr.write('Output file (\'-o\') missing.\n')
            sys.exit(1)

if __name__ == "__main__":
    main()
    
