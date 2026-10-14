/* Regression for synthetic SDL event union initialization. */
#include <SDL3/SDL.h>
#include <stdio.h>
extern int mg_test_key(int,int);
int main(void){
  if(!SDL_Init(SDL_INIT_EVENTS))return 1;
  for(int scan=4;scan<=44;scan++){
    for(int down=1;down>=0;down--){
      if(mg_test_key(scan,down)!=1)return 2;
      SDL_Event event;
      int seen=0;
      while(SDL_PollEvent(&event)){
        if(event.type!=SDL_EVENT_KEY_DOWN && event.type!=SDL_EVENT_KEY_UP)continue;
        if((int)event.key.scancode!=scan || event.key.repeat!=0 || event.key.windowID!=0 ||
           event.key.down!=(down!=0))return 3;
        seen++;
      }
      if(seen!=1)return 4;
    }
  }
  SDL_Quit();puts("Synthetic keyboard events passed: scancode, state, repeat, window ID");return 0;
}
