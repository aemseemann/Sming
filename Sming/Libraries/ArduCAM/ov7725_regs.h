#ifndef OV7725_REGS_H
#define OV7725_REGS_H
#include "ArduCAM.h"
//#include <avr/pgmspace.h>
const struct sensor_reg OV7725_QVGA[] PROGMEM =
{
  {0x32,0x00},
  {0x2a,0x00},
  {0x11,0x02},
  {0x12,0x46},//QVGA RGB565
  {0x12,0x06},

  
  {0x42,0x7f},
  {0x4d,0x00},//0x09
  {0x63,0xf0},
  {0x64,0xff},
  {0x65,0x20},
  {0x66,0x00},
  {0x67,0x00},
  {0x69,0x5d},  
 
  
  {0x13,0xff},
  {0x0d,0x81},//PLL
  {0x0f,0xc5},
  {0x14,0x11},
  {0x22,0xFF},//7f
  {0x23,0x01},
  {0x24,0x34},
  {0x25,0x3c},
  {0x26,0xa1},
  {0x2b,0x00},
  {0x6b,0xaa},
  {0x13,0xff},

  {0x90,0x0a},//
  {0x91,0x01},//
  {0x92,0x01},//
  {0x93,0x01},
  
  {0x94,0x5f},
  {0x95,0x53},
  {0x96,0x11},
  {0x97,0x1a},
  {0x98,0x3d},
  {0x99,0x5a},
  {0x9a,0x1e},
  
  {0x9b,0x00},//set luma 
  {0x9c,0x25},//set contrast 
  {0xa7,0x65},//set saturation  
  {0xa8,0x65},//set saturation 
  {0xa9,0x80},//set hue 
  {0xaa,0x80},//set hue 
  
  {0x9e,0x81},
  {0xa6,0x06},

  {0x7e,0x0c},
  {0x7f,0x16},
  {0x80,0x2a},
  {0x81,0x4e},
  {0x82,0x61},
  {0x83,0x6f},
  {0x84,0x7b},
  {0x85,0x86},
  {0x86,0x8e},
  {0x87,0x97},
  {0x88,0xa4},
  {0x89,0xaf},
  {0x8a,0xc5},
  {0x8b,0xd7},
  {0x8c,0xe8},
  {0x8d,0x20},

  {0x33,0x00},
  {0x22,0x99},
  {0x23,0x03},
  {0x4a,0x00},
  {0x49,0x13},
  {0x47,0x08},
  {0x4b,0x14},
  {0x4c,0x17},
  {0x46,0x05},
  {0x0e,0x75},
  {0x0c,0x90},
  {0x00,0xf0},
  {0x29,0x50},
  {0x2C,0x78},
		{0xff, 0xff},
};        


#endif
