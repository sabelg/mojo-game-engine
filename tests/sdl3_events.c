/* C-created SDL3 events independently exercise Mojo's event decoding. */
#include <SDL3/SDL.h>
int atlas_sdl3_fixture(int fixture){
 SDL_Event e;SDL_zero(e);
 switch(fixture){
 case 0:e.type=SDL_EVENT_KEY_DOWN;e.key.scancode=SDL_SCANCODE_A;e.key.key=SDLK_A;e.key.down=true;break;
 case 1:e.type=SDL_EVENT_KEY_DOWN;e.key.scancode=SDL_SCANCODE_A;e.key.key=SDLK_A;e.key.down=true;e.key.repeat=true;break;
 case 2:e.type=SDL_EVENT_KEY_UP;e.key.scancode=SDL_SCANCODE_A;e.key.key=SDLK_A;break;
 case 3:e.type=SDL_EVENT_TEXT_INPUT;e.text.text="Mara \xC3\xA9 \xE7\x8C\xAB";break;
 case 4:e.type=SDL_EVENT_MOUSE_WHEEL;e.wheel.y=3.0f;e.wheel.integer_y=3;e.wheel.direction=SDL_MOUSEWHEEL_FLIPPED;break;
 case 5:e.type=SDL_EVENT_WINDOW_FOCUS_LOST;break;
 case 6:e.type=SDL_EVENT_WINDOW_CLOSE_REQUESTED;break;
 default:return 0;
 }
 return SDL_PushEvent(&e);
}
