/* Execute the real HEX in upstream simavr. UART callback = UDR write, not TX pin.
   Usage: sim_test timers.hex cycles [rx_schedule.csv]
   Schedule lines: absolute_CPU_cycle,byte_value. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "sim_avr.h"
#include "sim_hex.h"
#include "sim_elf.h"
#include "sim_io.h"
#include "avr_uart.h"
#include "avr_ioport.h"
static avr_t *cpu;
static void uart_out(struct avr_irq_t *irq,uint32_t value,void *param){
 printf("UART,%llu,%u\n",(unsigned long long)cpu->cycle,value&255);
}
static void pin(struct avr_irq_t *irq,uint32_t value,void *param){
 printf("%s,%llu,%u\n",(char*)param,(unsigned long long)cpu->cycle,value&1);
}
int main(int argc,char **argv){
 if(argc<3)return 2;
 elf_firmware_t fw={0};sim_setup_firmware(argv[1],0,&fw,"sim_test");
 cpu=avr_make_mcu_by_name("atmega8");if(!cpu||avr_init(cpu))return 3;
 cpu->frequency=8000000;cpu->log=0;avr_load_firmware(cpu,&fw);
 uint32_t flags=0;avr_ioctl(cpu,AVR_IOCTL_UART_SET_FLAGS('0'),&flags);
 avr_irq_register_notify(avr_io_getirq(cpu,AVR_IOCTL_UART_GETIRQ('0'),UART_IRQ_OUTPUT),uart_out,NULL);
 avr_irq_register_notify(avr_io_getirq(cpu,AVR_IOCTL_IOPORT_GETIRQ('B'),IOPORT_IRQ_PIN1),pin,"OC1A");
 avr_irq_register_notify(avr_io_getirq(cpu,AVR_IOCTL_IOPORT_GETIRQ('B'),IOPORT_IRQ_PIN2),pin,"OC1B");
 avr_irq_t *rx=avr_io_getirq(cpu,AVR_IOCTL_UART_GETIRQ('0'),UART_IRQ_INPUT);
 FILE *input=argc>3?fopen(argv[3],"r"):NULL;
 unsigned long long at=~0ULL;unsigned byte=0;
 if(input&&fscanf(input,"%llu,%u",&at,&byte)!=2)at=~0ULL;
 unsigned long long stop=strtoull(argv[2],NULL,10),snapshot=10000;
 int running=0;unsigned stops=0;unsigned vector_a=0,vector_b=0,vector_tx=0,vector_rx=0;
 while(cpu->cycle<stop){
  if(cpu->cycle>=at){
   avr_raise_irq(rx,byte);printf("RX,%llu,%u\n",(unsigned long long)cpu->cycle,byte);
   if(fscanf(input,"%llu,%u",&at,&byte)!=2)at=~0ULL;
  }
  if(cpu->pc==0x0c)vector_a++;
  if(cpu->pc==0x0e)vector_b++;
  if(cpu->pc==0x18)vector_tx++;
  if(cpu->pc==0x16)vector_rx++;
  int state=avr_run(cpu);
  if(state==cpu_Done||state==cpu_Crashed){fprintf(stderr,"CPU state %d\n",state);return 4;}
  if(cpu->data[0x4e]&7)running=1;else if(running)stops++;
  if(cpu->cycle>=snapshot){
   printf("STATE,%llu,%u,%u,%u,%u,%u,%u\n",(unsigned long long)cpu->cycle,
    cpu->data[0x60]+256*cpu->data[0x61],cpu->data[0x62]+256*cpu->data[0x63],
    cpu->data[0x64],cpu->data[0x65],cpu->data[0x6b],cpu->data[0x68]);snapshot+=10000;
  }
 }
 printf("END,%llu,%u\n",(unsigned long long)cpu->cycle,stops);
 printf("VECTORS,%u,%u,%u,%u\n",vector_a,vector_b,vector_tx,vector_rx);
 if(input)fclose(input);avr_terminate(cpu);return 0;
}
