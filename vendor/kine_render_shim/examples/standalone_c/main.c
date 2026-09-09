#include "kine_filament_shim.h"

#include <SDL3/SDL.h>

#include <stdio.h>

int main(void)
{
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window* window = SDL_CreateWindow(
        "Kinemium Filament smoke",
        320,
        240,
        SDL_WINDOW_VULKAN | SDL_WINDOW_HIDDEN);
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        SDL_Quit();
        return 1;
    }

    KineFilamentContext* filament = Kine_Filament_CreateForSDLWindow(window, 320, 240);
    if (!filament) {
        fprintf(stderr, "Kine_Filament_CreateForSDLWindow failed\n");
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 1;
    }

    Kine_Filament_RenderFrame(filament, 1.0 / 60.0);
    Kine_Filament_Destroy(filament);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
