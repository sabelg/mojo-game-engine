/* Independent C-header oracle for the public layouts consumed by Mojo. */
#include <SDL3/SDL.h>
#include <stddef.h>
#include <stdio.h>
#define TYPE(t) printf("%s.size=%zu\n",#t,sizeof(t))
#define FIELD(t,f) printf("%s.%s=%zu\n",#t,#f,offsetof(t,f))
#define VALUE(v) printf("%s=%llu\n",#v,(unsigned long long)(v))
int main(void){
 TYPE(SDL_Event); TYPE(SDL_Surface); TYPE(SDL_DisplayMode); TYPE(SDL_AudioSpec); TYPE(SDL_KeyboardEvent);
 FIELD(SDL_Surface,flags);FIELD(SDL_Surface,format);FIELD(SDL_Surface,w);FIELD(SDL_Surface,h);FIELD(SDL_Surface,pitch);FIELD(SDL_Surface,pixels);FIELD(SDL_Surface,refcount);FIELD(SDL_Surface,reserved);
 FIELD(SDL_DisplayMode,displayID);FIELD(SDL_DisplayMode,format);FIELD(SDL_DisplayMode,w);FIELD(SDL_DisplayMode,h);FIELD(SDL_DisplayMode,pixel_density);FIELD(SDL_DisplayMode,refresh_rate);FIELD(SDL_DisplayMode,refresh_rate_numerator);FIELD(SDL_DisplayMode,refresh_rate_denominator);FIELD(SDL_DisplayMode,internal);
 FIELD(SDL_AudioSpec,format);FIELD(SDL_AudioSpec,channels);FIELD(SDL_AudioSpec,freq);
 FIELD(SDL_KeyboardEvent,type);FIELD(SDL_KeyboardEvent,reserved);FIELD(SDL_KeyboardEvent,timestamp);FIELD(SDL_KeyboardEvent,windowID);FIELD(SDL_KeyboardEvent,which);FIELD(SDL_KeyboardEvent,scancode);FIELD(SDL_KeyboardEvent,key);FIELD(SDL_KeyboardEvent,mod);FIELD(SDL_KeyboardEvent,raw);FIELD(SDL_KeyboardEvent,down);FIELD(SDL_KeyboardEvent,repeat);
 FIELD(SDL_TextInputEvent,text);FIELD(SDL_MouseWheelEvent,integer_y);FIELD(SDL_MouseWheelEvent,direction);
 VALUE(SDL_EVENT_WINDOW_FOCUS_LOST);VALUE(SDL_EVENT_WINDOW_CLOSE_REQUESTED);VALUE(SDL_EVENT_TEXT_INPUT);VALUE(SDL_EVENT_MOUSE_WHEEL);VALUE(SDL_EVENT_KEY_DOWN);VALUE(SDL_EVENT_KEY_UP);
 VALUE(SDL_WINDOW_VULKAN);VALUE(SDL_WINDOW_HIGH_PIXEL_DENSITY);VALUE(SDL_AUDIO_F32);VALUE(SDL_AUDIO_S16);
 return 0;
}
