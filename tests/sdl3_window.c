/* Native SDL3 lifecycle oracle, including real owned-window text input. */
#include <SDL3/SDL.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef struct Graphics Graphics;
extern Graphics *mg_open(const char *,int,int,int);
extern void mg_close(Graphics *);
extern const char *mg_error(void);
extern int mg_text_input(Graphics *,int);
extern int mg_resize(Graphics *,int,int);
extern int mg_width(Graphics *);
extern int mg_height(Graphics *);
extern uint32_t mg_mouse(Graphics *,int *,int *);
extern void mg_shadow_begin(Graphics *,const float *);
extern void mg_begin(Graphics *,const float *,float,float,float,float);
extern int mg_rect(Graphics *,float,float,float,float,float,float,float,float);
extern int mg_present(Graphics *);
extern int mg_validation_errors(Graphics *);
#define CHECK(x) do { if(!(x)){fprintf(stderr,"SDL3 lifecycle failed at line %d: %s; %s\n",__LINE__,#x,mg_error());goto failed;} }while(0)
int main(void){
 Graphics *g=NULL;
 CHECK(SDL_GetVersion()==SDL_VERSIONNUM(3,4,18));
 const float identity[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
 for(int pass=0;pass<2;pass++){
  g=mg_open("Atlas native SDL3 lifecycle",160,120,0);CHECK(g);
  int count=0;SDL_Window **windows=SDL_GetWindows(&count);CHECK(windows && count==1);
  SDL_Window *window=windows[0];SDL_free(windows);
  CHECK((SDL_GetWindowFlags(window)&(SDL_WINDOW_VULKAN|SDL_WINDOW_RESIZABLE))==(SDL_WINDOW_VULKAN|SDL_WINDOW_RESIZABLE));
  CHECK(mg_text_input(g,1)==0);CHECK(SDL_TextInputActive(window));
  CHECK(mg_text_input(g,0)==0);CHECK(!SDL_TextInputActive(window));
  SDL_WarpMouseInWindow(window,32.0f,24.0f);SDL_PumpEvents();SDL_Delay(10);
  int x=0,y=0;(void)mg_mouse(g,&x,&y);CHECK(abs(x-32)<=1 && abs(y-24)<=1);
  for(int frame=0;frame<8;frame++){
   if(frame==3){CHECK(mg_resize(g,257,193)==0);CHECK(SDL_SyncWindow(window));}
   SDL_PumpEvents();int width=0,height=0;CHECK(SDL_GetWindowSizeInPixels(window,&width,&height));
   CHECK(width==mg_width(g) && height==mg_height(g));
   mg_shadow_begin(g,identity);mg_begin(g,identity,0,1,0,0);
   CHECK(mg_rect(g,8,8,40,30,.2f,.8f,.5f,1)==0);CHECK(mg_present(g)==0);
  }
  CHECK(mg_validation_errors(g)==0);mg_close(g);g=NULL;
  windows=SDL_GetWindows(&count);SDL_free(windows);CHECK(count==0);
 }
 SDL_Quit();puts("SDL3 lifecycle passed: pinned runtime, owned text input, mouse, Vulkan surface/present/resize, close and reopen");return 0;
failed:
 if(g){mg_close(g);}
 SDL_Quit();return 1;
}
