#!/bin/bash
# Run the Akai Firmware Updater with HID write interception.
# After the window opens, click every button in the app.
# The captured bytes will be saved to /tmp/hid_capture.log
set -e

WINE_EXE="$HOME/.wine/drive_c/Program Files (x86)/Akai Professional/MPK mini IV Firmware Updater/Akai Professional MPK mini IV Firmware Updater.exe"
SHIM=/tmp/hidraw_intercept.so
LOG=/tmp/hid_capture.log

if [ ! -f "$SHIM" ]; then
    echo "Building HID intercept shim..."
    cat > /tmp/hidraw_intercept.c << 'CEOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <sys/ioctl.h>
#include <linux/hidraw.h>

static ssize_t (*real_write)(int,const void*,size_t)=NULL;
static int     (*real_open)(const char*,int,...)=NULL;
static int     (*real_ioctl)(int,unsigned long,...)=NULL;
static int hid_fds[65536]={0};
static FILE *logfp=NULL;

static void log_bytes(const char *tag,const void *buf,size_t n){
    if(!logfp) return;
    fprintf(logfp,"[hid] %s len=%zu: ",tag,n);
    const unsigned char *b=buf;
    for(size_t i=0;i<n&&i<64;i++) fprintf(logfp,"%02X ",b[i]);
    fprintf(logfp,"\n");fflush(logfp);
}
__attribute__((constructor)) static void init(){
    real_write=dlsym(RTLD_NEXT,"write");
    real_open=dlsym(RTLD_NEXT,"open");
    real_ioctl=dlsym(RTLD_NEXT,"ioctl");
    char *lf=getenv("HIDRAW_LOG");
    if(lf){logfp=fopen(lf,"w");if(logfp)setvbuf(logfp,NULL,_IONBF,0);}
}
int open(const char *p,int f,...){
    va_list a;va_start(a,f);mode_t m=va_arg(a,mode_t);va_end(a);
    int fd=real_open(p,f,m);
    if(fd>=0&&fd<65536&&p&&strstr(p,"hidraw")){
        hid_fds[fd]=1;
        if(logfp){fprintf(logfp,"[hid] OPEN %s fd=%d\n",p,fd);fflush(logfp);}
    }
    return fd;
}
ssize_t write(int fd,const void *b,size_t n){
    if(fd>=0&&fd<65536&&hid_fds[fd]&&n>0) log_bytes("WRITE",b,n);
    return real_write(fd,b,n);
}
int ioctl(int fd,unsigned long req,...){
    va_list a;va_start(a,req);void *arg=va_arg(a,void*);va_end(a);
    int r=real_ioctl(fd,req,arg);
    if(fd>=0&&fd<65536&&hid_fds[fd])
        log_bytes("IOCTL",arg,64);
    return r;
}
CEOF
    gcc -O2 -shared -fPIC -o "$SHIM" /tmp/hidraw_intercept.c -ldl
    echo "Shim built: $SHIM"
fi

rm -f "$LOG"
echo "Starting Firmware Updater with HID capture..."
echo "Log will be written to: $LOG"
echo ""
echo "IMPORTANT: When the window opens, click EVERY button."
echo "           Especially 'Check for Update' / 'Connect' / anything visible."
echo "           Then close the app and check $LOG"
echo ""

HIDRAW_LOG="$LOG" LD_PRELOAD="$SHIM" \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/xauth_dCVQhN \
    wine "$WINE_EXE"

echo ""
echo "=== HID CAPTURE RESULTS ==="
if [ -s "$LOG" ]; then
    cat "$LOG"
    echo ""
    echo "SUCCESS! Run: python3 ~/SelahOS-Dev/tools/mpk-mini-iv/replay_hid_init.py $LOG"
else
    echo "Nothing captured — the app may not have connected to the device."
    echo "Try Path 2: sudo modprobe usbmon then run capture_hid_init.py"
fi
