/* Exercises the real Vulkan surface/swapchain path on a disposable X display. */
#include <SDL3/SDL.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
typedef struct Graphics Graphics;
Graphics *mg_open(const char *,int,int,int);
void mg_close(Graphics *);
const char *mg_error(void);
int mg_resize(Graphics *,int,int);
int mg_hdr(Graphics *,int);
int mg_width(Graphics *);
int mg_height(Graphics *);
void mg_shadow_begin(Graphics *,const float *);
void mg_begin(Graphics *,const float *,float,float,float,float);
int mg_rect(Graphics *,float,float,float,float,float,float,float,float);
int mg_present(Graphics *);
int mg_snapshot(Graphics *,const char *);
int mg_validation_errors(Graphics *);
double mg_stage_ms(Graphics *,int);
int mg_present_mode(Graphics *);
double mg_detail_ms(Graphics *,int);
int mg_surface_info(Graphics *,int);
int main(void){
    Graphics *g=mg_open("Vulkan swapchain regression",320,240,0);
    if(!g){fprintf(stderr,"%s\n",mg_error());return 1;}
    if(mg_hdr(g,1)<0)goto failed;
    const float identity[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
    for(int frame=0;frame<120;frame++){
        if(frame==31&&mg_hdr(g,0)<0)goto failed;
        if(frame==47&&mg_hdr(g,1)<0)goto failed;
        if(frame==3&&mg_resize(g,517,293)<0)goto failed;
        if(frame==7&&mg_resize(g,280,380)<0)goto failed;
        SDL_PumpEvents();SDL_Delay(10);
        if(mg_width(g)<=0||mg_height(g)<=0)goto failed;
        mg_shadow_begin(g,identity);mg_begin(g,identity,0,1,0,0);
        if(mg_rect(g,10,10,80,60,0.2f,0.8f,0.5f,1)<0)goto failed;
        if(frame==119&&mg_snapshot(g,"build/vulkan-window.bmp")<0)goto failed;
        if(mg_present(g)<0)goto failed;
        if(mg_present_mode(g)!=1 && mg_present_mode(g)!=2)goto failed;
        for(int stage=0;stage<5;stage++){
            double ms=mg_stage_ms(g,stage);
            if(!isfinite(ms) || (stage<4 ? ms<0 : ms < -1))goto failed;
        }
        for(int detail=0;detail<6;detail++)if(!isfinite(mg_detail_ms(g,detail))||mg_detail_ms(g,detail)<0)goto failed;
        int minimum=mg_surface_info(g,1),maximum=mg_surface_info(g,2),count=mg_surface_info(g,3);
        if(minimum<1||count<minimum||(maximum&&count>maximum)||!(mg_surface_info(g,0)&(1<<mg_present_mode(g))))goto failed;
        if(frame%19==0 && mg_present(g)<0)goto failed; /* semaphore reuse without a new render */
    }
    if(mg_validation_errors(g))goto failed;
    mg_close(g);puts("HDR Vulkan window passed (including in-flight mode switches): surface, acquire/present, swapchain resize, snapshot");return 0;
failed:
    fprintf(stderr,"%s\n",mg_error());mg_close(g);return 1;
}
