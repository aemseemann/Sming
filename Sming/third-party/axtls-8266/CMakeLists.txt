# subdir for axtls

set(AXTLS_SOURCES
    "crypto/aes.c"
    "crypto/bigint.c"
    "crypto/hmac.c"
    "crypto/md5.c"
    "crypto/rc4.c"
    "crypto/rsa.c"
    "crypto/sha1.c"
    "crypto/sha256.c"
    "crypto/sha384.c"
    "crypto/sha512.c"
    "ssl/asn1.c"
    "ssl/gen_cert.c"
    "ssl/loader.c"
    "ssl/os_port.c"
    "ssl/p12.c"
    "ssl/tls1.c"
    "ssl/tls1_clnt.c"
    "ssl/tls1_svr.c"
    "ssl/x509.c"
    "crypto/crypto_misc.c"
)

add_library(axtls STATIC ${AXTLS_SOURCES})

target_include_directories(axtls PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/crypto"
    "${CMAKE_CURRENT_SOURCE_DIR}/ssl"
    "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_definitions(axtls PRIVATE
    ESP8266
    WITH_PGM_READ_HELPER
    __ets__
)

target_compile_definitions(axtls INTERFACE
    LWIP_RAW=1
    ENABLE_SSL=1
)

if (SMING_SSL_DEBUG STREQUAL 1)
    target_compile_definitions(axtls PUBLIC
        SSL_DEBUG=1
        DEBUG_TLS_MEM=1
        AXL_DEBUG=1
    )
endif()

set_property(TARGET axtls PROPERTY C_STANDARD 99)
# TBD: reason for missing flags?
# -mtext-section-literals
# -finline-functions
# TODO: what is the reason for -Os -O2? Is a combination of '-O' flags even possible?
target_compile_options(axtls PRIVATE -Wall -Os -g -O2 -gno-record-gcc-switches)
