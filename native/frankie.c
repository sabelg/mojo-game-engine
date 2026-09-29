/* Original asset I/O and audio adapter for the Mojo Yo Frankie port. */
#include <SDL2/SDL.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
extern int mg_mesh(void *, const float *, int, const uint32_t *, int);
int yf_mesh(void *g, const char *path) {
  FILE *f=fopen(path,"rb"); if(!f)return -1;
  uint32_t h[2];
  if(fread(h,4,2,f)!=2 || h[0]!=0x314d4659 || h[1]==0 || h[1]>3000000 || h[1]%3){fclose(f);return -1;}
  size_t n=h[1];float *v=malloc(n*8*sizeof(float));uint32_t *idx=malloc(n*4);
  if(!v || !idx){free(v);free(idx);fclose(f);return -1;}
  int ok=fread(v,32,n,f)==n && fgetc(f)==EOF;fclose(f);
  for(size_t i=0;i<n*8 && ok;i++)if(!isfinite(v[i]))ok=0;
  for(size_t i=0;i<n;i++)idx[i]=(uint32_t)i;
  int result=ok?mg_mesh(g,v,(int)n*8,idx,(int)n):-1;
  free(v);free(idx);return result;
}
#define SOUNDS 12
static SDL_AudioDeviceID device;
static float *samples[SOUNDS];static int lengths[SOUNDS];
typedef struct {int id,pos,loop;float gain;} Voice;
static Voice voices[12];static int muted;
static void mix(void *unused, Uint8 *stream,int bytes){
  (void)unused;float *out=(float*)stream;int n=bytes/4;
  for(int i=0;i<n;i++){
    float value=0;
    for(int j=0;j<12;j++){
      Voice *v=&voices[j];if(v->id<0)continue;
      if(v->pos>=lengths[v->id]){if(v->loop)v->pos=0;else{v->id=-1;continue;}}
      value+=samples[v->id][v->pos++]*v->gain;
    }
    out[i]=muted?0:fmaxf(-1,fminf(1,value));
  }
}
int yf_audio_open(void){
  if(device)return 0;
  if(SDL_InitSubSystem(SDL_INIT_AUDIO)<0){fprintf(stderr,"Audio initialization failed: %s\n",SDL_GetError());return -1;}
  SDL_AudioSpec spec={0};spec.freq=44100;spec.format=AUDIO_F32SYS;spec.channels=1;spec.samples=1024;spec.callback=mix;
  for(int j=0;j<12;j++)voices[j].id=-1;
  device=SDL_OpenAudioDevice(NULL,0,&spec,NULL,0);if(!device){fprintf(stderr,"Audio device failed: %s\n",SDL_GetError());return -1;}
  const char *names[SOUNDS]={"sfx_jump.wav","item_pickup.wav","life_pickup.wav","TailWhip.wav","sheepHit.wav","FrankieDeath.wav","sfx_throw.wav","end_level.wav","amb_forest.wav","msx_caves.wav","msx_peachvalley.wav","MenuMusic1.wav"};
  for(int i=0;i<SOUNDS;i++){
    char path[512];snprintf(path,sizeof(path),"third_party/yofrankie/audio/%s",names[i]);
    SDL_AudioSpec src;Uint8 *data;Uint32 bytes;
    if(!SDL_LoadWAV(path,&src,&data,&bytes))continue;
    SDL_AudioCVT cvt;
    if(SDL_BuildAudioCVT(&cvt,src.format,src.channels,src.freq,AUDIO_F32SYS,1,44100)<0){SDL_FreeWAV(data);continue;}
    cvt.len=(int)bytes;cvt.buf=malloc((size_t)cvt.len*cvt.len_mult);
    if(cvt.buf){SDL_memcpy(cvt.buf,data,bytes);if(SDL_ConvertAudio(&cvt)==0){samples[i]=(float*)cvt.buf;lengths[i]=cvt.len_cvt/4;}else free(cvt.buf);}
    SDL_FreeWAV(data);
  }
  SDL_PauseAudioDevice(device,0);return 0;
}
void yf_audio_play(int id,int loop){
  if(!device || id<0 || id>=SOUNDS || !lengths[id])return;
  SDL_LockAudioDevice(device);
  int slot=0;if(!loop){slot=1;for(int j=1;j<12;j++)if(voices[j].id<0){slot=j;break;}}
  voices[slot]=(Voice){id,0,loop,loop?.35f:.65f};SDL_UnlockAudioDevice(device);
}
void yf_audio_mute(int value){if(device)SDL_LockAudioDevice(device);muted=value;if(device)SDL_UnlockAudioDevice(device);}
void yf_audio_close(void){if(device){SDL_CloseAudioDevice(device);device=0;}for(int i=0;i<SOUNDS;i++){free(samples[i]);samples[i]=NULL;lengths[i]=0;}}
/* Automated window/input regression; no input is sent outside this SDL app. */
int yf_test_key(int code,int pressed){
  SDL_Event event;
  SDL_zero(event); /* Zero the full union, including repeat and window ID. */
  event.type=pressed?SDL_KEYDOWN:SDL_KEYUP;
  event.key.keysym.scancode=(SDL_Scancode)code;event.key.state=pressed?SDL_PRESSED:SDL_RELEASED;
  return SDL_PushEvent(&event);
}
int yf_audio_loaded(void){int n=0;for(int i=0;i<SOUNDS;i++)if(lengths[i]>0)n++;return n;}
