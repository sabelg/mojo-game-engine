/* Exercises the real Vulkan surface/swapchain path on a disposable X display. */
#include <SDL2/SDL.h>
#include <stdint.h>
#include <stdio.h>
typedef struct Graphics Graphics;
Graphics *mg_open(const char *,int,int,int);
void mg_close(Graphics *);
const char *mg_error(void);
int mg_resize(Graphics *,int,int);
int mg_width(Graphics *);
int mg_height(Graphics *);
void mg_shadow_begin(Graphics *,const float *);
void mg_begin(Graphics *,const float *,float,float,float,float);
int mg_rect(Graphics *,float,float,float,float,float,float,float,float);
int mg_present(Graphics *);
int mg_snapshot(Graphics *,const char *);
int mg_validation_errors(Graphics *);
int main(void){
    Graphics *g=mg_open("Vulkan swapchain regression",320,240,0);
    if(!g){fprintf(stderr,"%s\n",mg_error());return 1;}
    const float identity[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
    for(int frame=0;frame<12;frame++){
        if(frame==3&&mg_resize(g,517,293)<0)goto failed;
        if(frame==7&&mg_resize(g,280,380)<0)goto failed;
        SDL_PumpEvents();SDL_Delay(10);
        if(mg_width(g)<=0||mg_height(g)<=0)goto failed;
        mg_shadow_begin(g,identity);mg_begin(g,identity,0,1,0,0);
        if(mg_rect(g,10,10,80,60,0.2f,0.8f,0.5f,1)<0)goto failed;
        if(frame==11&&mg_snapshot(g,"build/vulkan-window.bmp")<0)goto failed;
        if(mg_present(g)<0)goto failed;
    }
    if(mg_validation_errors(g))goto failed;
    mg_close(g);puts("Vulkan window passed: surface, acquire/present, swapchain resize, snapshot");return 0;
failed:
    fprintf(stderr,"%s\n",mg_error());mg_close(g);return 1;
}
