/* Virtual SDL controller: mapped controls, radial deadzone, focus and reconnect. */
#include <SDL3/SDL.h>
#include <math.h>
#include <stdio.h>
#include <stdint.h>
extern uint32_t mg_pad_poll(int);
extern double mg_pad_axis(int);
extern int mg_pad_connected(void);
extern void mg_pad_close(void);
int main(void){
  SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS,"1");
  if(!SDL_Init(SDL_INIT_GAMEPAD))return 1;
  for(int pass=0;pass<2;pass++){
    SDL_VirtualJoystickDesc desc; SDL_zero(desc); SDL_INIT_INTERFACE(&desc);
    desc.type=SDL_JOYSTICK_TYPE_GAMEPAD;desc.naxes=6;desc.nbuttons=15;
    SDL_JoystickID id=SDL_AttachVirtualJoystick(&desc);
    if(!id)return 2;
    SDL_Joystick *stick=SDL_OpenJoystick(id);
    if(!stick)return 3;
    (void)mg_pad_poll(1);
    if(!mg_pad_connected())return 4;
    SDL_SetJoystickVirtualAxis(stick,0,2000);SDL_UpdateJoysticks();
    (void)mg_pad_poll(1);if(mg_pad_axis(0)!=0)return 5;
    SDL_SetJoystickVirtualAxis(stick,0,32767);SDL_SetJoystickVirtualAxis(stick,1,32767);
    SDL_SetJoystickVirtualButton(stick,SDL_GAMEPAD_BUTTON_SOUTH,1);SDL_UpdateJoysticks();
    if(!(mg_pad_poll(1)&1))return 6;
    double x=mg_pad_axis(0),y=mg_pad_axis(1);
    if(x<.70||y<.70||hypot(x,y)>1.000001)return 7;
    if(mg_pad_poll(0)!=0||mg_pad_axis(0)!=0)return 8;
    SDL_CloseJoystick(stick);SDL_DetachVirtualJoystick(id);(void)mg_pad_poll(1);
    if(mg_pad_connected())return 9;
  }
  mg_pad_close();SDL_Quit();puts("Controller passed: mapping, radial deadzone, normalized diagonal, focus suppression, reconnect");return 0;
}
