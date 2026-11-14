#include "kine_game.h"

#define TEXT(s) ((kine_game_string){s, sizeof(s) - 1})

static const kine_game_api *game;
static kine_game_instance part;
static double elapsed;

static int32_t KINE_GAME_CALL start(const kine_game_api *api)
{
    if (api->abi_major != KINE_GAME_ABI_MAJOR || api->size < sizeof(*api))
        return 0;
    game = api;
    elapsed = 0;
    kine_game_instance workspace = game->get_service(game->context, TEXT("Workspace"));
    part = game->create(game->context, TEXT("Part"));
    if (!part || !workspace) return 0;

    kine_game_value value = {.kind = KINE_GAME_STRING, .data.string = TEXT("NativeGamePart")};
    if (!game->set(game->context, part, TEXT("Name"), &value)) return 0;
    value = (kine_game_value){.kind = KINE_GAME_BOOLEAN, .data.boolean = 1};
    if (!game->set(game->context, part, TEXT("Anchored"), &value)) return 0;
    value = (kine_game_value){.kind = KINE_GAME_INSTANCE, .data.instance = workspace};
    if (!game->set(game->context, part, TEXT("Parent"), &value)) return 0;
    if (game->find_child(game->context, workspace, TEXT("NativeGamePart")) != part) return 0;
    if (!game->get(game->context, part, TEXT("Anchored"), &value) ||
        value.kind != KINE_GAME_BOOLEAN || !value.data.boolean) return 0;

    game->log(game->context, TEXT("Native game started"));
    return 1;
}

static void KINE_GAME_CALL update(double delta)
{
    elapsed += delta;
    kine_game_value position = {
        .kind = KINE_GAME_VECTOR3,
        .data.vector3 = {0, (float)(4 + elapsed), 0}
    };
    if (!game->set(game->context, part, TEXT("Position"), &position) || elapsed >= 2.0)
        game->request_exit(game->context);
}

static void KINE_GAME_CALL stop(void)
{
    if (!game) return;
    if (part) game->call(game->context, part, TEXT("Destroy"), NULL, 0, NULL, 0);
    game->log(game->context, TEXT("Native game stopped"));
    game = NULL;
    part = NULL;
}

KINE_GAME_EXPORT const kine_game_desc *KINE_GAME_CALL kine_game_entry(void)
{
    static const kine_game_desc desc = {
        sizeof(kine_game_desc), KINE_GAME_ABI_MAJOR, KINE_GAME_ABI_MINOR, 0,
        start, update, stop
    };
    return &desc;
}
