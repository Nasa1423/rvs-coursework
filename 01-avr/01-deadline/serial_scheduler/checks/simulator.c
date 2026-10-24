/* Unmodified upstream simavr. OUTPUT callback observes OUT UDR, not TX pin. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "sim_avr.h"
#include "sim_hex.h"
#include "sim_elf.h"
#include "sim_io.h"
#include "avr_uart.h"
#include "avr_timer.h"
static avr_t *cpu;
static avr_timer_t *timer;
static avr_uart_t *uart;
static int active=0,first=0;
static void uart_out(struct avr_irq_t *irq,uint32_t value,void *param){
 if(active && first){
  unsigned addr=active==1?0x68:0x6a;
  uint16_t due=cpu->data[addr]+256*cpu->data[addr+1];
  uint16_t counter=(cpu->cycle-timer->tov_base)&65535;
  printf("START,%llu,%d,%u,%u,%d\n",(unsigned long long)cpu->cycle,active,due,counter,(int16_t)(counter-due));
  first=0;
 }
 printf("UART,%llu,%d,%u\n",(unsigned long long)cpu->cycle,active,value&255);
}
int main(int argc,char **argv){
 if(argc<3)return 2;
 elf_firmware_t fw={0};sim_setup_firmware(argv[1],0,&fw,"sim_test");
 cpu=avr_make_mcu_by_name("atmega8");if(!cpu||avr_init(cpu))return 3;
 cpu->frequency=8000000;cpu->log=0;avr_load_firmware(cpu,&fw);
 for(avr_io_t *p=cpu->io_port;p;p=p->next)if(!strcmp(p->kind,"timer")&&((avr_timer_t*)p)->name=='1')timer=(avr_timer_t*)p;
 for(avr_io_t *p=cpu->io_port;p;p=p->next)if(!strcmp(p->kind,"uart"))uart=(avr_uart_t*)p;
 if(!timer || !uart)return 5;
 uint32_t flags=0;avr_ioctl(cpu,AVR_IOCTL_UART_SET_FLAGS('0'),&flags);
 avr_irq_register_notify(avr_io_getirq(cpu,AVR_IOCTL_UART_GETIRQ('0'),UART_IRQ_OUTPUT),uart_out,NULL);
 avr_irq_t *rx=avr_io_getirq(cpu,AVR_IOCTL_UART_GETIRQ('0'),UART_IRQ_INPUT);
 FILE *input=argc>3?fopen(argv[3],"r"):NULL;
 unsigned long long at=~0ULL;unsigned byte=0;
 if(input&&fscanf(input,"%llu,%u",&at,&byte)!=2)at=~0ULL;
 unsigned long long stop=strtoull(argv[2],NULL,10);int running=0;unsigned stops=0;
 while(cpu->cycle<stop){
  if(cpu->cycle>=at){avr_raise_irq(rx,byte);if(fscanf(input,"%llu,%u",&at,&byte)!=2)at=~0ULL;}
  if(cpu->pc==0x0c){active=1;first=1;}
  if(cpu->pc==0x0e){active=2;first=1;}
  int reti=cpu->flash[cpu->pc]==0x18 && cpu->flash[cpu->pc+1]==0x95;
  int state=avr_run(cpu);if(reti)active=0;
  /* Pinned simavr mis-models ATmega8 UBRRH/UCSRC alias and parity.
     Set the documented 8 MHz / 500 kbaud / 8N1 frame duration only.
     CPU instructions, Timer1 and output timestamps remain unmodified. */
  uart->cycles_per_byte=160;
  if(state==cpu_Done||state==cpu_Crashed)return 4;
  if(cpu->data[0x4e]&7)running=1;else if(running)stops++;
 }
 printf("END,%u,%u,%u,%u,%u,%u\n",stops,cpu->data[0x60]+256*cpu->data[0x61],cpu->data[0x62]+256*cpu->data[0x63],cpu->data[0x64],cpu->data[0x65],cpu->data[0x66]+256*cpu->data[0x67]);
 if(input)fclose(input);avr_terminate(cpu);return 0;
}
