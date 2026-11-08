// Included by kine_filament_shim.cpp: uses its mesh/material upload helpers.
#include <array>

namespace {
constexpr int KINE_VP_ATLAS_SIZE = 2048;
constexpr size_t KINE_VP_MAX_PAGES = 16; // 512 MiB colour+depth at the absolute peak.
struct KineViewportPage {
    Texture *color = nullptr, *depth = nullptr;
    RenderTarget *target = nullptr;
    KineSkiaImage *image = nullptr;
    int cell = 0;
    std::vector<bool> occupied;
#if KINE_FILAMENT_USE_VULKAN
    VkImage vkImage = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    backend::Platform::ExternalImageHandle external;
#else
    unsigned int glTexture = 0;
#endif
};
struct KineViewportScratch {
    int width=0,height=0;
    Scene *clearScene = nullptr;
    Entity clearEntity;
    MaterialInstance *clearMaterial = nullptr;
    Texture *color = nullptr, *depth = nullptr;
    RenderTarget *target = nullptr;
    int cell = 0;
};
struct KineViewportChunk {
    KineMesh *mesh = nullptr;
    KineTexHandle *texture = nullptr;
    KineBatchKey key;
    Entity entity;
    InstanceBuffer *instances = nullptr;
    MaterialInstance *material = nullptr;
    std::vector<MaterialInstance *> extraMaterials;
    size_t count = 0;
    uint32_t flags = 0;
};
}
struct KineFilamentViewport {
    KineFilamentContext *ctx = nullptr;
    KineViewportPage *page = nullptr;
    Scene *scene = nullptr;
    View *historyView = nullptr;
    uint8_t historyWarmup = 0;
    Scene *copyScene = nullptr;
    Entity copyEntity, lightEntity, shadowBoundsEntity;
    bool hasShadowCasters = false;
    MaterialInstance *copyMaterial = nullptr;
    IndirectLight *ambientLight = nullptr;
    ColorGrading *colorGrading = nullptr;
    KineViewportScratch *scratch = nullptr;
    int renderedWidth = 0, renderedHeight = 0;
    float cameraFar = 100.0f;
    uint64_t effectsHash = 0;
    std::array<float,5> copyEffects{};
    std::vector<KineViewportChunk> chunks;
    KineViewportSettings settings{};
    uint64_t version = 0;
    int slot = -1;
    bool requested = false, dirty = true, ready = false, initialized = false;
};
struct KineViewportPool {
    std::vector<KineFilamentViewport *> handles;
    std::vector<std::unique_ptr<KineViewportPage>> pages;
    Material *material = nullptr, *clearMaterial = nullptr;
    Texture *environment = nullptr;
    KineMesh *shadowBoundsMesh = nullptr;
    View *view = nullptr, *copyView = nullptr, *clearView = nullptr;
    std::vector<std::unique_ptr<KineViewportScratch>> scratch;
    Camera *camera = nullptr;
    Scene *presentScene = nullptr;
    Entity presentEntity;
    MaterialInstance *presentMaterial = nullptr;
    Entity cameraEntity;
    std::unordered_map<uint64_t, KineFilamentMesh *> meshes;
    uint64_t renders = 0;
};
#if KINE_FILAMENT_USE_VULKAN
namespace {
template <typename T> T kine_vp_device_proc(const KineFilamentVulkanBackend &b, const char *name) {
    auto instanceProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(b.getInstanceProcAddr);
    auto deviceProc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(instanceProc(reinterpret_cast<VkInstance>(b.instance), "vkGetDeviceProcAddr"));
    return reinterpret_cast<T>(deviceProc(reinterpret_cast<VkDevice>(b.device), name));
}
bool kine_vp_allocate_image(KineFilamentContext *ctx, KineViewportPage &page) {
    if (!ctx->useFilamentOwnedCompositor) return false;
    KineFilamentVulkanBackend b{};
    if (!Kine_Filament_GetVulkanBackend(ctx, &b)) return false;
    auto device = reinterpret_cast<VkDevice>(b.device);
    auto create = kine_vp_device_proc<PFN_vkCreateImage>(b, "vkCreateImage");
    auto requirements = kine_vp_device_proc<PFN_vkGetImageMemoryRequirements>(b, "vkGetImageMemoryRequirements");
    auto allocate = kine_vp_device_proc<PFN_vkAllocateMemory>(b, "vkAllocateMemory");
    auto bind = kine_vp_device_proc<PFN_vkBindImageMemory>(b, "vkBindImageMemory");
    VkImageCreateInfo info{}; info.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    info.imageType = VK_IMAGE_TYPE_2D; info.format = VK_FORMAT_R8G8B8A8_UNORM;
    info.extent = {KINE_VP_ATLAS_SIZE, KINE_VP_ATLAS_SIZE, 1};
    info.mipLevels = info.arrayLayers = 1; info.samples = VK_SAMPLE_COUNT_1_BIT;
    info.tiling = VK_IMAGE_TILING_OPTIMAL;
    info.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (create(device, &info, nullptr, &page.vkImage) != VK_SUCCESS) return false;
    VkMemoryRequirements req{}; requirements(device, page.vkImage, &req);
    auto instanceProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(b.getInstanceProcAddr);
    auto memoryProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(instanceProc(reinterpret_cast<VkInstance>(b.instance), "vkGetPhysicalDeviceMemoryProperties"));
    VkPhysicalDeviceMemoryProperties properties{};
    memoryProperties(reinterpret_cast<VkPhysicalDevice>(b.physicalDevice), &properties);
    uint32_t type = UINT32_MAX;
    for (uint32_t i = 0; i < properties.memoryTypeCount; ++i) {
        if ((req.memoryTypeBits & (1u << i)) && (properties.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {type = i; break;}
    }
    if (type == UINT32_MAX) return false;
    VkMemoryAllocateInfo allocation{}; allocation.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocation.allocationSize = req.size; allocation.memoryTypeIndex = type;
    if (allocate(device, &allocation, nullptr, &page.memory) != VK_SUCCESS || bind(device, page.vkImage, page.memory, 0) != VK_SUCCESS) return false;
    auto *external = new KineViewportExternalImage(); external->image = page.vkImage; external->size = KINE_VP_ATLAS_SIZE;
    page.external = backend::Platform::ExternalImageHandle(external);
    page.color = Texture::Builder().width(KINE_VP_ATLAS_SIZE).height(KINE_VP_ATLAS_SIZE).levels(1)
        .format(Texture::InternalFormat::RGBA8)
        .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE | Texture::Usage::BLIT_SRC)
        .external().build(*ctx->engine);
    if (!page.color) return false;
    page.color->setExternalImage(*ctx->engine, page.external);
    return true;
}
}
#endif
namespace {
void kine_vp_free_page(KineFilamentContext *ctx, KineViewportPage &p) {
    if (p.image) Kine_Skia_Image_Destroy(p.image);
    if (p.target) ctx->engine->destroy(p.target);
    if (p.color) ctx->engine->destroy(p.color);
    if (p.depth) ctx->engine->destroy(p.depth);
#if KINE_FILAMENT_USE_VULKAN
    // Only called after all front-end views are destroyed and GPU work is drained.
    ctx->engine->flushAndWait();
    p.external.clear();
    KineFilamentVulkanBackend b{};
    if (Kine_Filament_GetVulkanBackend(ctx, &b)) {
        auto device = reinterpret_cast<VkDevice>(b.device);
        if (p.vkImage) kine_vp_device_proc<PFN_vkDestroyImage>(b, "vkDestroyImage")(device, p.vkImage, nullptr);
        if (p.memory) kine_vp_device_proc<PFN_vkFreeMemory>(b, "vkFreeMemory")(device, p.memory, nullptr);
    }
#else
    ctx->engine->flushAndWait();
    if (p.glTexture) {GLuint id = p.glTexture; glDeleteTextures(1, &id);}
#endif
}
bool kine_vp_init_pool(KineFilamentContext *ctx) {
    auto &pool = *ctx->viewportPool;
    if (pool.view) return true;
    pool.material = Material::Builder().package(KINE_VIEWPORT_PACKAGE_KINE_VIEWPORT_DATA, KINE_VIEWPORT_PACKAGE_KINE_VIEWPORT_SIZE).build(*ctx->engine);
    pool.clearMaterial = Material::Builder().package(KINE_VIEWPORT_CLEAR_PACKAGE_KINE_VIEWPORT_CLEAR_DATA, KINE_VIEWPORT_CLEAR_PACKAGE_KINE_VIEWPORT_CLEAR_SIZE).build(*ctx->engine);
    pool.view = ctx->engine->createView();
    pool.environment=Texture::Builder().width(1).height(1).levels(1).sampler(Texture::Sampler::SAMPLER_CUBEMAP).format(Texture::InternalFormat::RGBA8).build(*ctx->engine);
    static const uint8_t environmentPixels[24]={255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255};
    pool.environment->setImage(*ctx->engine,0,0,0,0,1,1,6,Texture::PixelBufferDescriptor(environmentPixels,sizeof(environmentPixels),Texture::Format::RGBA,Texture::Type::UBYTE));
    // Filament's directional shadow range uses caster bounds for its receiver
    // depth range too. A shared degenerate triangle contributes only bounds:
    // it writes no colour/depth, and lets receive-only parts keep their shadows.
    pool.shadowBoundsMesh=new KineMesh();
    pool.shadowBoundsMesh->vertices={ {0,0,0,0,1,0,0,0},{0,0,0,0,1,0,0,0},{0,0,0,0,1,0,0,0} };
    pool.shadowBoundsMesh->indices={0,1,2};pool.shadowBoundsMesh->indexCount=3;
    uploadMesh(pool.shadowBoundsMesh,ctx->engine);
    pool.copyView = ctx->engine->createView();
    pool.clearView = ctx->engine->createView();
    pool.cameraEntity = EntityManager::get().create();
    pool.camera = ctx->engine->createCamera(pool.cameraEntity);
    pool.view->setCamera(pool.camera);
    pool.copyView->setCamera(pool.camera);
    pool.clearView->setCamera(pool.camera);pool.clearView->setPostProcessingEnabled(false);
    pool.clearView->setShadowingEnabled(false);pool.clearView->setAntiAliasing(AntiAliasing::NONE);
    pool.copyView->setPostProcessingEnabled(false);
    pool.copyView->setShadowingEnabled(false);
    pool.copyView->setAntiAliasing(AntiAliasing::NONE);
    pool.view->setBlendMode(View::BlendMode::TRANSLUCENT);
    pool.view->setPostProcessingEnabled(false);
    pool.view->setShadowingEnabled(false);
    pool.view->setAntiAliasing(AntiAliasing::NONE);
    // A zero-alpha draw into the normal target ensures Filament acquires and
    // releases the shared swapchain even for a UI-only frame of offscreen views.
    pool.presentScene = ctx->engine->createScene();
    pool.presentEntity = EntityManager::get().create();
    pool.presentMaterial = ctx->gizmoMaterial->createInstance();
    const math::float4 transparent{0,0,0,0}; kine_set_chunk_colors(pool.presentMaterial, &transparent, 1);
    RenderableManager::Builder(1).boundingBox({{0,0,0},{1,1,1}})
        .material(0,pool.presentMaterial).geometry(0,RenderableManager::PrimitiveType::TRIANGLES,
            ctx->postProcessQuadMesh->vb,ctx->postProcessQuadMesh->ib,0,ctx->postProcessQuadMesh->indexCount)
        .culling(false).castShadows(false).receiveShadows(false).build(*ctx->engine,pool.presentEntity);
    pool.presentScene->addEntity(pool.presentEntity);
    return pool.material && pool.clearMaterial && pool.view && pool.camera;
}
KineViewportPage *kine_vp_get_page(KineFilamentContext *ctx, int cell) {
    auto &pool = *ctx->viewportPool;
    for (auto &p : pool.pages) if (p->cell == cell && std::find(p->occupied.begin(), p->occupied.end(), false) != p->occupied.end()) return p.get();
    // Empty pages can change size buckets without reallocating GPU images.
    for (auto &p : pool.pages) if (std::find(p->occupied.begin(), p->occupied.end(), true) == p->occupied.end()) {
        p->cell = cell; p->occupied.assign((KINE_VP_ATLAS_SIZE/cell)*(KINE_VP_ATLAS_SIZE/cell),false);
        return p.get();
    }
    if (pool.pages.size() >= KINE_VP_MAX_PAGES) return nullptr;
    auto p = std::make_unique<KineViewportPage>();
    p->cell = cell; p->occupied.resize((KINE_VP_ATLAS_SIZE/cell)*(KINE_VP_ATLAS_SIZE/cell), false);
#if KINE_FILAMENT_USE_VULKAN
    if (!kine_vp_allocate_image(ctx, *p)) {kine_vp_free_page(ctx, *p); return nullptr;}
#else
    p->glTexture = createGLColorTexture(KINE_VP_ATLAS_SIZE, KINE_VP_ATLAS_SIZE);
    p->color = Texture::Builder().width(KINE_VP_ATLAS_SIZE).height(KINE_VP_ATLAS_SIZE).levels(1)
        .format(Texture::InternalFormat::RGBA8).usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
        .import(p->glTexture).build(*ctx->engine);
#endif
    p->depth = Texture::Builder().width(KINE_VP_ATLAS_SIZE).height(KINE_VP_ATLAS_SIZE).levels(1)
        .format(Texture::InternalFormat::DEPTH32F).usage(Texture::Usage::DEPTH_ATTACHMENT).build(*ctx->engine);
    p->target = RenderTarget::Builder().texture(RenderTarget::AttachmentPoint::COLOR, p->color)
        .texture(RenderTarget::AttachmentPoint::DEPTH, p->depth).build(*ctx->engine);
    if (!p->target) {kine_vp_free_page(ctx, *p); return nullptr;}
    auto *result = p.get(); pool.pages.push_back(std::move(p)); return result;
}
KineViewportScratch *kine_vp_scratch(KineFilamentContext *ctx, int width, int height) {
    auto &pool = *ctx->viewportPool;
    for (auto &p : pool.scratch) if (p->width==width && p->height==height) return p.get();
    auto p = std::make_unique<KineViewportScratch>(); p->cell = std::max(width,height);p->width=width;p->height=height;
    p->color = Texture::Builder().width(width).height(height).levels(1).format(Texture::InternalFormat::RGBA8)
        .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE).build(*ctx->engine);
    p->depth = Texture::Builder().width(width).height(height).levels(1).format(Texture::InternalFormat::DEPTH32F)
        .usage(Texture::Usage::DEPTH_ATTACHMENT).build(*ctx->engine);
    p->target = RenderTarget::Builder().texture(RenderTarget::AttachmentPoint::COLOR,p->color)
        .texture(RenderTarget::AttachmentPoint::DEPTH,p->depth).build(*ctx->engine);
    p->clearScene=ctx->engine->createScene();p->clearEntity=EntityManager::get().create();
    p->clearMaterial=pool.clearMaterial->createInstance();p->clearMaterial->setParameter("clearOnly",1.0f);
    p->clearMaterial->setParameter("source",ctx->whiteTex,TextureSampler());
    p->clearMaterial->setParameter("sourceScale",math::float2{0,0});p->clearMaterial->setParameter("sourceOffset",math::float2{0,0});
    RenderableManager::Builder(1).boundingBox({{0,0,0},{1,1,1}}).material(0,p->clearMaterial)
        .geometry(0,RenderableManager::PrimitiveType::TRIANGLES,ctx->postProcessQuadMesh->vb,ctx->postProcessQuadMesh->ib,0,ctx->postProcessQuadMesh->indexCount)
        .culling(false).castShadows(false).receiveShadows(false).build(*ctx->engine,p->clearEntity);
    p->clearScene->addEntity(p->clearEntity);
    auto *result = p.get(); pool.scratch.push_back(std::move(p)); return result;
}
void kine_vp_release_scene(KineFilamentViewport *vp) {
    auto *ctx = vp->ctx;
    if (ctx->viewportPool->view) ctx->viewportPool->view->setColorGrading(nullptr);
    if (vp->historyView) {vp->historyView->setColorGrading(nullptr);ctx->engine->destroy(vp->historyView);vp->historyView=nullptr;}
    if (vp->copyScene) {vp->copyScene->remove(vp->copyEntity);ctx->engine->destroy(vp->copyEntity);EntityManager::get().destroy(vp->copyEntity);ctx->engine->destroy(vp->copyScene);}
    if (!vp->shadowBoundsEntity.isNull()) {vp->scene->remove(vp->shadowBoundsEntity);ctx->engine->destroy(vp->shadowBoundsEntity);EntityManager::get().destroy(vp->shadowBoundsEntity);}
    if (vp->copyMaterial) ctx->engine->destroy(vp->copyMaterial);
    if (!vp->lightEntity.isNull()) {vp->scene->remove(vp->lightEntity);ctx->engine->destroy(vp->lightEntity);EntityManager::get().destroy(vp->lightEntity);}
    if (vp->ambientLight) {vp->scene->setIndirectLight(nullptr);ctx->engine->destroy(vp->ambientLight);}
    if (vp->colorGrading) ctx->engine->destroy(vp->colorGrading);
    if (vp->scene) ctx->engine->destroy(vp->scene);
}
void kine_vp_destroy_chunk(KineFilamentViewport *vp, KineViewportChunk &chunk) {
    vp->scene->remove(chunk.entity);
    vp->ctx->engine->destroy(chunk.entity); EntityManager::get().destroy(chunk.entity);
    if (chunk.instances) vp->ctx->engine->destroy(chunk.instances);
    if (chunk.material) vp->ctx->engine->destroy(chunk.material);
    kine_destroy_extra_materials(vp->ctx,chunk.extraMaterials);
}
void kine_vp_update_chunks(KineFilamentViewport *vp,const KineFilamentDrawItem *items,uint32_t count) {
    auto *ctx=vp->ctx;auto &pool=*ctx->viewportPool;
    struct Group {KineBatchKey key;std::vector<math::mat4f> transforms;std::vector<math::float4> colors;std::vector<float> uvs;};
    std::vector<Group> groups;
    for(uint32_t i=0;i<count;++i) {
        auto key=kine_draw_item_key(items[i]);auto *mesh=key.mesh;
        if(!mesh || !mesh->vb || !mesh->ib)continue;
        auto it=std::find_if(groups.begin(),groups.end(),[&](const Group &g){return g.key==key;});
        if(it==groups.end()){groups.push_back({key,{},{},{}});it=groups.end()-1;}
        it->transforms.push_back(kine_from_row_major(items[i].transform));
        const float alpha=key.materialKind==KINE_MAT_DEFAULT ? std::clamp(items[i].transmission,0.0f,1.0f) : 1.0f;
        it->colors.push_back({items[i].r,items[i].g,items[i].b,alpha});
        it->uvs.push_back(items[i].param3>0 ? items[i].param3 : 1.0f);
    }
    size_t index=0;
    for(auto &g:groups)for(size_t offset=0;offset<g.transforms.size();offset+=64) {
        auto *mesh=g.key.mesh;size_t n=std::min(size_t(64),g.transforms.size()-offset);
        if(index<vp->chunks.size() && (!(vp->chunks[index].key==g.key) || vp->chunks[index].count!=n)) {
            for(size_t i=index;i<vp->chunks.size();++i)kine_vp_destroy_chunk(vp,vp->chunks[i]);vp->chunks.resize(index);
        }
        if(index==vp->chunks.size()) {
            KineViewportChunk c{};c.mesh=mesh;c.texture=g.key.texture;c.key=g.key;c.count=n;
            auto *base=!g.key.shader && g.key.materialKind==KINE_MAT_DEFAULT && g.key.transmission<0.999f ? pool.material : kine_select_material(ctx,g.key.materialKind,g.key.shader,false);
            c.material=base->createInstance();kine_apply_material_params(ctx,c.material,g.key,false);
            kine_set_chunk_colors(c.material,g.colors.data()+offset,n);kine_set_chunk_uvs(c.material,g.uvs.data()+offset,n);
            c.instances=InstanceBuffer::Builder(n).build(*ctx->engine);c.instances->setLocalTransforms(g.transforms.data()+offset,n,0);
            c.entity=EntityManager::get().create();
            RenderableManager::Builder builder(kine_mesh_primitive_count(ctx,g.key,false));
            kine_bind_mesh_geometry(ctx,builder,g.key,base,c.material,c.extraMaterials,g.colors.data()+offset,g.uvs.data()+offset,n,false);
            builder.boundingBox(kine_compute_batch_bounds(mesh,g.transforms.data()+offset,n,g.key.shader,g.key.materialKind==KINE_MAT_WATER ? .65f*ctx->water.strength*ctx->water.height : 0.0f))
                .instances(n,c.instances).culling(g.key.culling).castShadows(g.key.castShadow).receiveShadows(g.key.receiveShadow);
            if(g.key.materialKind==KINE_MAT_GLASS)builder.channel(2);
            if(!mesh->bones.empty() && mesh->skinMatrices.size()==mesh->bones.size())builder.skinning(mesh->skinMatrices.size(),mesh->skinMatrices.data());
            builder.build(*ctx->engine,c.entity);vp->scene->addEntity(c.entity);vp->chunks.push_back(c);
        } else {
            auto &c=vp->chunks[index];c.instances->setLocalTransforms(g.transforms.data()+offset,n,0);
            if (!kine_uses_imported_materials(ctx,c.key,false)) {
                kine_apply_material_params(ctx,c.material,c.key,false);
                kine_set_chunk_uvs(c.material,g.uvs.data()+offset,n);
            }
            kine_set_chunk_colors(c.material,g.colors.data()+offset,n);
            for (auto *mi : c.extraMaterials) kine_set_chunk_colors(mi,g.colors.data()+offset,n);
            auto &rm=ctx->engine->getRenderableManager();rm.setAxisAlignedBoundingBox(rm.getInstance(c.entity),kine_compute_batch_bounds(mesh,g.transforms.data()+offset,n,c.key.shader,c.key.materialKind==KINE_MAT_WATER ? .65f*ctx->water.strength*ctx->water.height : 0.0f));
            if(!mesh->bones.empty() && mesh->skinMatrices.size()==mesh->bones.size())rm.setBones(rm.getInstance(c.entity),mesh->skinMatrices.data(),mesh->skinMatrices.size(),0);
        }
        ++index;
    }
    for(size_t i=index;i<vp->chunks.size();++i)kine_vp_destroy_chunk(vp,vp->chunks[i]);vp->chunks.resize(index);
}

}
static void kine_viewport_destroy_shader_batches(KineFilamentContext *ctx, KineFilamentShader *shader) {
    if (!ctx || !ctx->viewportPool) return;
    for (auto *vp : ctx->viewportPool->handles) {
        if (!vp) continue;
        const bool usesShader = std::any_of(vp->chunks.begin(), vp->chunks.end(),
            [shader](const KineViewportChunk &chunk) { return chunk.key.shader == shader; });
        if (!usesShader) continue;
        for (auto &chunk : vp->chunks) kine_vp_destroy_chunk(vp, chunk);
        vp->chunks.clear();
        vp->initialized = false;
        vp->ready = false;
        vp->dirty = true;
    }
}

static void kine_viewport_update_shader_uniforms(KineFilamentContext *ctx, KineFilamentShader *shader) {
    if (!ctx || !ctx->viewportPool) return;
    for (auto *vp : ctx->viewportPool->handles) {
        if (!vp) continue;
        for (auto &chunk : vp->chunks) {
            if (chunk.key.shader != shader) continue;
            kine_apply_material_params(ctx, chunk.material, chunk.key, false);
            vp->dirty = true;
        }
    }
}

static void kine_viewport_invalidate_batches(KineFilamentContext *ctx, const KineMesh *mesh, const KineTexHandle *texture) {
    if (!ctx || !ctx->viewportPool) return;
    for (auto *vp : ctx->viewportPool->handles) {
        if (!vp) continue;
        const bool matches=std::any_of(vp->chunks.begin(),vp->chunks.end(),
            [mesh,texture](const KineViewportChunk &chunk) {
                return (mesh && chunk.mesh==mesh) || (texture && chunk.texture==texture);
            });
        if (!matches) continue;
        for (auto &chunk:vp->chunks) kine_vp_destroy_chunk(vp,chunk);
        vp->chunks.clear();vp->initialized=false;vp->ready=false;vp->dirty=true;
    }
}

KINE_API KineFilamentViewport *Kine_Filament_Viewport_Create(KineFilamentContext *ctx) {
    if (!ctx || !ctx->engine) return nullptr;
    if (!ctx->viewportPool) ctx->viewportPool = new KineViewportPool();
    auto *vp = new KineFilamentViewport(); vp->ctx = ctx;
    ctx->viewportPool->handles.push_back(vp); return vp;
}
KINE_API void Kine_Filament_Viewport_Destroy(KineFilamentViewport *vp) {
    if (!vp) return;
    auto *ctx = vp->ctx;
    if (ctx && ctx->engine && ctx->viewportPool) {
        for (auto &c : vp->chunks) kine_vp_destroy_chunk(vp, c);
        kine_vp_release_scene(vp);
        if (vp->page && vp->slot >= 0) vp->page->occupied[vp->slot] = false;
        auto &handles = ctx->viewportPool->handles; handles.erase(std::remove(handles.begin(), handles.end(), vp), handles.end());
    }
    delete vp;
}
KINE_API void Kine_Filament_Viewport_Begin(KineFilamentContext *ctx) {
    if (ctx && ctx->viewportPool) for (auto *vp : ctx->viewportPool->handles) vp->requested = false;
}
KINE_API bool Kine_Filament_Viewport_IsValid(KineFilamentViewport *vp, KineFilamentContext *ctx) {return vp && vp->ctx == ctx && ctx;}
KINE_API void Kine_Filament_Viewport_Touch(KineFilamentViewport *vp) {if (vp) vp->requested = true;}
KINE_API KineFilamentMesh *Kine_Filament_Viewport_Primitive(KineFilamentContext *ctx,int shape) {
    if(!ctx || !ctx->engine)return nullptr;
    if(!ctx->viewportPool)ctx->viewportPool=new KineViewportPool();
    const uint64_t key=(uint64_t(1)<<63)|uint32_t(shape);auto &meshes=ctx->viewportPool->meshes;
    auto found=meshes.find(key);if(found!=meshes.end())return found->second;
    auto *mesh=Kine_Filament_CreateMesh(ctx,shape);if(mesh)meshes.emplace(key,mesh);return mesh;
}
KINE_API KineFilamentMesh *Kine_Filament_Viewport_Mesh(KineFilamentContext *ctx, uint64_t key, const void *data, size_t size, const char *hint) {
    if (!ctx || !ctx->engine || !data || !size) return nullptr;
    if (!ctx->viewportPool) ctx->viewportPool = new KineViewportPool();
    auto &meshes = ctx->viewportPool->meshes;
    auto it = meshes.find(key); if (it != meshes.end()) return it->second;
    auto *mesh = Kine_Filament_CreateMeshFromMemory(ctx, data, size, hint);
    if (mesh) meshes.emplace(key, mesh); return mesh;
}
static BloomOptions kine_vp_bloom(const KineFilamentViewport *vp) {
    auto bloom=vp->ctx->view->getBloomOptions();const auto &s=vp->settings;
    if(s.effectMask&1) {const auto *p=s.bloom;bloom.enabled=p[0]>0;bloom.strength=std::clamp(p[1],0.0f,1.0f);bloom.resolution=uint32_t(std::clamp(p[2],8.0f,2048.0f));bloom.levels=6;bloom.threshold=p[3]>0;bloom.lensFlare=p[4]>0;}
    return bloom;
}
static void kine_vp_prepare_copy_effects(KineFilamentViewport *vp) {
    if(!vp->copyMaterial || !vp->scratch)return;
    const auto bloom=kine_vp_bloom(vp);
    const std::array<float,5> values{vp->settings.postProcessing && bloom.enabled ? bloom.strength : 0.0f,bloom.threshold ? 0.8f : 0.0f,std::clamp(float(bloom.resolution)*0.25f,2.0f,32.0f),1.0f/vp->scratch->width,1.0f/vp->scratch->height};
    if(values==vp->copyEffects)return;vp->copyEffects=values;
    vp->copyMaterial->setParameter("haloStrength",values[0]);
    vp->copyMaterial->setParameter("haloThreshold",bloom.threshold ? 0.8f : 0.0f);
    vp->copyMaterial->setParameter("haloRadius",std::clamp(float(bloom.resolution)*0.25f,2.0f,32.0f));
    vp->copyMaterial->setParameter("haloTexel",math::float2{1.0f/vp->scratch->width,1.0f/vp->scratch->height});
}

KINE_API bool Kine_Filament_Viewport_Update(KineFilamentViewport *vp, const KineViewportSettings *settings,
        const KineFilamentDrawItem *items, uint32_t count, uint64_t version) {
    if (!vp || !settings || !vp->ctx || (count && !items)) return false;
    if (settings->width <= 0 || settings->height <= 0) return false;
    auto *ctx = vp->ctx;
#if KINE_FILAMENT_USE_VULKAN
    if (!ctx->useFilamentOwnedCompositor) return false;
#endif
    vp->requested = true;
    if (!kine_vp_init_pool(ctx)) return false;
    auto adjusted = *settings; adjusted.width = std::clamp(adjusted.width, 1, 1024); adjusted.height = std::clamp(adjusted.height, 1, 1024);
    int cell = 32; while (cell < std::max(adjusted.width, adjusted.height)) cell *= 2;
    if (vp->page && vp->page->cell != cell) {vp->page->occupied[vp->slot] = false; vp->page = nullptr; vp->slot = -1; vp->ready = false;}
    if (!vp->page) {
        vp->page = kine_vp_get_page(ctx, cell); if (!vp->page) return false;
        auto it = std::find(vp->page->occupied.begin(), vp->page->occupied.end(), false);
        vp->slot = int(it-vp->page->occupied.begin()); vp->page->occupied[vp->slot] = true; vp->dirty = true;
    }
    int scratchWidth=32,scratchHeight=32;
    while(scratchWidth<adjusted.width)scratchWidth*=2;while(scratchHeight<adjusted.height)scratchHeight*=2;
    auto *scratch=kine_vp_scratch(ctx,scratchWidth,scratchHeight);
    const bool scratchChanged=vp->scratch!=scratch;vp->scratch=scratch;
    if (!vp->scene) {
        vp->scene = ctx->engine->createScene(); vp->copyScene = ctx->engine->createScene();
        vp->copyEntity = EntityManager::get().create();
        vp->copyMaterial = ctx->viewportPool->clearMaterial->createInstance();
        RenderableManager::Builder(1).boundingBox({{0,0,0},{1,1,1}}).material(0,vp->copyMaterial)
            .geometry(0,RenderableManager::PrimitiveType::TRIANGLES,ctx->postProcessQuadMesh->vb,ctx->postProcessQuadMesh->ib,0,ctx->postProcessQuadMesh->indexCount)
            .culling(false).castShadows(false).receiveShadows(false).build(*ctx->engine,vp->copyEntity);
        vp->copyScene->addEntity(vp->copyEntity);
        vp->lightEntity = EntityManager::get().create();
        LightManager::Builder(LightManager::Type::DIRECTIONAL).color({1,1,1}).intensity(float(M_PI)).direction({-1,-1,-1})
            .castShadows(true).shadowOptions(kine_make_sun_shadow_options(512,1,0,0.5f,40,true,false)).build(*ctx->engine,vp->lightEntity);
        vp->scene->addEntity(vp->lightEntity);
        vp->shadowBoundsEntity=EntityManager::get().create();auto *proxy=ctx->viewportPool->shadowBoundsMesh;
        RenderableManager::Builder(1).boundingBox({{0,0,0},{0.001f,0.001f,0.001f}}).material(0,vp->scratch->clearMaterial)
            .geometry(0,RenderableManager::PrimitiveType::TRIANGLES,proxy->vb,proxy->ib,0,3)
            .culling(false).castShadows(true).receiveShadows(false).build(*ctx->engine,vp->shadowBoundsEntity);
        vp->scene->addEntity(vp->shadowBoundsEntity);
    }
    if (!vp->initialized || scratchChanged) {
    vp->copyMaterial->setParameter("source",vp->scratch->color,TextureSampler(TextureSampler::MinFilter::LINEAR,TextureSampler::MagFilter::LINEAR));
    const float u = 1.0f, v = 1.0f;
#if KINE_FILAMENT_USE_VULKAN
    vp->copyMaterial->setParameter("sourceScale",math::float2{u,-v});
    vp->copyMaterial->setParameter("sourceOffset",math::float2{0,1});
#else
    vp->copyMaterial->setParameter("sourceScale",math::float2{u,v});
    vp->copyMaterial->setParameter("sourceOffset",math::float2{0,0});
#endif
    }
    const bool geometryChanged=!vp->initialized || version!=vp->version;
    const bool settingsChanged=!vp->initialized || memcmp(&vp->settings,&adjusted,sizeof(adjusted))!=0;
    if (geometryChanged) {kine_vp_update_chunks(vp, items, count); vp->version = version; vp->dirty = true;vp->historyWarmup=0;}
    if (settingsChanged) {
        if (!vp->ambientLight || memcmp(vp->settings.ambient,adjusted.ambient,sizeof(adjusted.ambient)) != 0) {
            if (vp->ambientLight) {vp->scene->setIndirectLight(nullptr);ctx->engine->destroy(vp->ambientLight);}
            math::float3 sh[1] = {{adjusted.ambient[0],adjusted.ambient[1],adjusted.ambient[2]}};
            vp->ambientLight = IndirectLight::Builder().reflections(ctx->viewportPool->environment).irradiance(1,sh).intensity(1.0f).build(*ctx->engine);
            vp->scene->setIndirectLight(vp->ambientLight);
        }
        auto &lm = ctx->engine->getLightManager(); auto instance = lm.getInstance(vp->lightEntity);
        auto direction = math::float3{adjusted.lightDirection[0],adjusted.lightDirection[1],adjusted.lightDirection[2]};
        direction = length(direction)<0.0001f ? math::float3{0,-1,0} : normalize(direction);
        lm.setDirection(instance,direction); lm.setColor(instance,{adjusted.lightColor[0],adjusted.lightColor[1],adjusted.lightColor[2]});
        lm.setShadowCaster(instance,adjusted.shadows != 0);
        if (!vp->initialized || vp->settings.effectMask != adjusted.effectMask || memcmp(vp->settings.color,adjusted.color,sizeof(adjusted.color)) != 0) {
            ctx->viewportPool->view->setColorGrading(nullptr);
            if(vp->historyView)vp->historyView->setColorGrading(nullptr);
            if (vp->colorGrading) {ctx->engine->destroy(vp->colorGrading);vp->colorGrading=nullptr;}
            const auto *c=adjusted.color;
            if ((adjusted.effectMask&8) && c[0]>0) vp->colorGrading=ColorGrading::Builder().exposure(c[1]).contrast(std::max(c[2],0.001f)).saturation(std::max(c[3],0.0f))
                .channelMixer({c[4],0,0},{0,c[5],0},{0,0,c[6]}).build(*ctx->engine);
        }
        vp->settings=adjusted;vp->dirty=true;vp->historyWarmup=0;
    }
    if(geometryChanged || settingsChanged) {
    Box previewBounds{};bool hasBounds=false;vp->hasShadowCasters=false;
    float previewFar=10.0f;const math::float3 eye{adjusted.camera[3],adjusted.camera[7],adjusted.camera[11]};
    for(uint32_t i=0;i<count;++i)if(auto *mesh=reinterpret_cast<KineMesh *>(items[i].mesh)) {
        auto bounds=rigidTransform(mesh->localBounds,kine_from_row_major(items[i].transform));
        if(items[i].shader)bounds.halfExtent+=math::float3{items[i].shader->boundsPadding};
        previewFar=std::max(previewFar,length(bounds.center-eye)+length(bounds.halfExtent)+1.0f);
        if(hasBounds)previewBounds.unionSelf(bounds);else {previewBounds=bounds;hasBounds=true;}
        vp->hasShadowCasters |= (items[i].flags & KINE_FILAMENT_DRAW_CAST_SHADOWS)!=0;
    }
    auto &rm=ctx->engine->getRenderableManager();auto proxy=rm.getInstance(vp->shadowBoundsEntity);
    if(hasBounds)rm.setAxisAlignedBoundingBox(proxy,previewBounds);
    rm.setMaterialInstanceAt(proxy,0,vp->scratch->clearMaterial);
    vp->cameraFar=previewFar*2.0f;
    auto &lightManager=ctx->engine->getLightManager();
    auto shadowOptions=kine_make_sun_shadow_options(512,1,previewFar,0.5f,previewFar,true,false);
    shadowOptions.constantBias=0.001f;shadowOptions.normalBias=0.1f;shadowOptions.polygonOffsetConstant=0.25f;shadowOptions.polygonOffsetSlope=0.5f;
    lightManager.setShadowOptions(lightManager.getInstance(vp->lightEntity),shadowOptions);
    }
    for(auto &c:vp->chunks)if(c.key.materialKind==KINE_MAT_WATER || c.key.materialKind==KINE_MAT_FORCEFIELD) {kine_apply_material_params(ctx,c.material,c.key,false);vp->dirty=true;}
    kine_vp_prepare_copy_effects(vp);
    vp->initialized = true; return true;
}
// Hash values rather than option-struct padding, so static previews stay cached.
static uint64_t kine_vp_global_effects_hash(KineFilamentContext *ctx) {
    uint64_t hash=14695981039346656037ull;
    auto add=[&](auto value) {const auto *p=reinterpret_cast<const uint8_t *>(&value);for(size_t i=0;i<sizeof(value);++i) hash=(hash^p[i])*1099511628211ull;};
    auto b=ctx->view->getBloomOptions();add(b.enabled);add(b.strength);add(b.resolution);add(b.levels);add(b.threshold);add(b.lensFlare);
    auto a=ctx->view->getAmbientOcclusionOptions();add(a.enabled);add(a.radius);add(a.power);add(a.intensity);add(a.quality);add(a.aoType);
    auto d=ctx->view->getDepthOfFieldOptions();add(d.enabled);add(d.cocScale);add(d.cocAspectRatio);add(d.maxApertureDiameter);add(d.maxForegroundCOC);add(d.maxBackgroundCOC);
    auto v=ctx->view->getVignetteOptions();add(v.enabled);add(v.midPoint);add(v.roundness);add(v.feather);add(v.color.x);add(v.color.y);add(v.color.z);add(v.color.w);
    auto r=ctx->view->getScreenSpaceReflectionsOptions();add(r.enabled);add(r.thickness);add(r.bias);add(r.maxDistance);add(r.stride);
    auto m=ctx->view->getMultiSampleAntiAliasingOptions();add(m.enabled);add(m.sampleCount);
    add(ctx->view->getAntiAliasing());add(ctx->view->getDithering());add(ctx->view->getRenderQuality().hdrColorBuffer);
    add(ctx->view->getColorGrading());add(ctx->camera->getFocusDistance());
    return hash;
}
static View *kine_vp_configure_view(KineFilamentViewport *vp) {
    auto *ctx=vp->ctx;const auto &s=vp->settings;
    const bool ssr=s.postProcessing && ((s.effectMask&32) ? s.reflections[0]>0 : ctx->view->getScreenSpaceReflectionsOptions().enabled);
    if(ssr && !vp->historyView) {vp->historyView=ctx->engine->createView();vp->historyView->setCamera(ctx->viewportPool->camera);vp->historyWarmup=0;}
    if(!ssr && vp->historyView) {vp->historyView->setColorGrading(nullptr);ctx->engine->destroy(vp->historyView);vp->historyView=nullptr;vp->historyWarmup=0;}
    // SSR samples the preceding image. Only opt-in previews need a private
    // lightweight View/history; they still share the same Engine and device.
    auto *view=vp->historyView ? vp->historyView : ctx->viewportPool->view;
    view->setPostProcessingEnabled(s.postProcessing!=0);view->setShadowingEnabled(s.shadows!=0 && vp->hasShadowCasters);
    view->setShadowType(ShadowType::PCF);
    auto bloom=kine_vp_bloom(vp);
    view->setBloomOptions(bloom);
    auto ao=ctx->view->getAmbientOcclusionOptions();
    if(s.effectMask&2) {const auto *p=s.ao;ao.enabled=p[0]>0;ao.radius=std::clamp(p[1],0.0f,10.0f);ao.power=std::max(p[2],0.001f);ao.intensity=std::max(p[3],0.0f);ao.quality=kine_quality_from_int(int(p[4]));ao.aoType=p[5]==1 ? AmbientOcclusionOptions::AmbientOcclusionType::GTAO : AmbientOcclusionOptions::AmbientOcclusionType::SAO;}
    ao.enabled &= s.postProcessing!=0;view->setAmbientOcclusionOptions(ao);
    auto dof=ctx->view->getDepthOfFieldOptions();
    if(s.effectMask&4) {const auto *p=s.dof;dof.enabled=p[0]>0;dof.cocScale=std::max(p[1],0.0f);dof.maxApertureDiameter=std::max(p[2],0.0f);dof.maxForegroundCOC=uint16_t(std::clamp(p[4],0.0f,32.0f));dof.maxBackgroundCOC=uint16_t(std::clamp(p[5],0.0f,32.0f));}
    view->setDepthOfFieldOptions(dof);
    ctx->viewportPool->camera->setFocusDistance((s.effectMask&4) ? std::max(s.dof[3],0.051f) : ctx->camera->getFocusDistance());
    auto vignette=ctx->view->getVignetteOptions();
    if(s.effectMask&16) {const auto *p=s.vignette;vignette.enabled=p[0]>0;vignette.midPoint=std::clamp(p[1],0.0f,1.0f);vignette.roundness=std::clamp(p[2],0.0f,1.0f);vignette.feather=std::clamp(p[3],0.0f,1.0f);vignette.color={p[4],p[5],p[6],std::clamp(p[7],0.0f,1.0f)};}
    view->setVignetteOptions(vignette);
    auto reflections=ctx->view->getScreenSpaceReflectionsOptions();
    if(s.effectMask&32) {const auto *p=s.reflections;reflections.enabled=p[0]>0;reflections.thickness=std::max(p[1],0.0f);reflections.bias=std::max(p[2],0.0f);reflections.maxDistance=std::max(p[3],0.0f);reflections.stride=std::max(p[4],0.001f);}
    reflections.enabled &= s.postProcessing!=0;view->setScreenSpaceReflectionsOptions(reflections);
    auto aa=ctx->view->getAntiAliasing();auto msaa=ctx->view->getMultiSampleAntiAliasingOptions();
    if(s.effectMask&64) {aa=s.antialiasing[3]>0 && s.antialiasing[0]>0 ? AntiAliasing::FXAA : AntiAliasing::NONE;msaa.enabled=s.antialiasing[3]>0 && s.antialiasing[1]>0;msaa.sampleCount=kine_clamp_u8(int(s.antialiasing[2]),1,8);}
    view->setAntiAliasing(aa);view->setMultiSampleAntiAliasingOptions(msaa);
    // Shared views cannot share temporal history between independent cameras.
    TemporalAntiAliasingOptions temporal{};temporal.enabled=false;view->setTemporalAntiAliasingOptions(temporal);
    view->setDithering((s.effectMask&128) ? (s.dithering ? Dithering::TEMPORAL : Dithering::NONE) : ctx->view->getDithering());
    auto quality=ctx->view->getRenderQuality();if(s.effectMask&256) quality.hdrColorBuffer=kine_quality_from_int(s.quality);view->setRenderQuality(quality);
    view->setColorGrading((s.effectMask&8) ? vp->colorGrading : const_cast<ColorGrading *>(ctx->view->getColorGrading()));
    return view;
}

static void kine_viewport_render_queued(KineFilamentContext *ctx) {
    if (!ctx || !ctx->viewportPool || !ctx->viewportPool->view) return;
    auto &pool = *ctx->viewportPool;
    for (auto *vp : pool.handles) {
        if (!vp->requested || !vp->dirty || !vp->page || !vp->scene) continue;
        auto &s = vp->settings;
        pool.camera->setModelMatrix(math::mat4(kine_from_row_major(s.camera)));
        pool.camera->setProjection(std::clamp(double(s.fieldOfView),1.0,120.0), double(s.width)/double(s.height), 0.05, vp->cameraFar);
        pool.camera->setExposure(1.0f); // Unitless preview lighting, independent of the world exposure.
        int columns = KINE_VP_ATLAS_SIZE/vp->page->cell;
        int x = (vp->slot%columns)*vp->page->cell, y = (vp->slot/columns)*vp->page->cell;
        // A transparent final postprocess blit blends into its destination.
        // Explicitly zero the scratch target before that blit, including when
        // the scene becomes empty or the view shrinks within a size bucket.
        pool.clearView->setBlendMode(View::BlendMode::OPAQUE);
        pool.clearView->setScene(vp->scratch->clearScene);pool.clearView->setRenderTarget(vp->scratch->target);
        pool.clearView->setViewport({0,0,uint32_t(vp->scratch->width),uint32_t(vp->scratch->height)});
        Renderer::ClearOptions scratchClear{};scratchClear.clear=false;scratchClear.discard=false;
        ctx->renderer->setClearOptions(scratchClear);ctx->renderer->render(pool.clearView);
        auto *renderView=kine_vp_configure_view(vp);
        renderView->setBlendMode(View::BlendMode::TRANSLUCENT);
        renderView->setScene(vp->scene);renderView->setRenderTarget(vp->scratch->target);
        // Cover the entire scratch attachment; subrect final blits sample outside
        // their colour history on this backend. The camera keeps the UI aspect.
        renderView->setViewport({0,0,uint32_t(vp->scratch->width),uint32_t(vp->scratch->height)});
        Renderer::ClearOptions clear{};clear.clear=false;clear.discard=false;clear.clearColor={0,0,0,0};
        ctx->renderer->setClearOptions(clear);ctx->renderer->render(renderView);
        // Effects run at the origin of a shared scratch target. An opaque GPU
        // copy then replaces this atlas rectangle, including zero-alpha pixels.
        // Full replacement prevents stale pixels without CPU copies or waits.
        // Clear the complete reserved slot, including pixels left by a larger
        // previous rectangle. Filtering must never find old object fragments.
        pool.clearView->setBlendMode(View::BlendMode::OPAQUE);
        pool.clearView->setScene(vp->scratch->clearScene);pool.clearView->setRenderTarget(vp->page->target);
        pool.clearView->setViewport({x,y,uint32_t(vp->page->cell),uint32_t(vp->page->cell)});
        Renderer::ClearOptions slotClear{};slotClear.clear=false;slotClear.discard=false;
        ctx->renderer->setClearOptions(slotClear);ctx->renderer->render(pool.clearView);
        pool.copyView->setBlendMode(View::BlendMode::OPAQUE);
        pool.copyView->setScene(vp->copyScene);pool.copyView->setRenderTarget(vp->page->target);
        pool.copyView->setViewport({x,y,uint32_t(s.width),uint32_t(s.height)});
        clear.clear=false;clear.discard=false;
        ctx->renderer->setClearOptions(clear);ctx->renderer->render(pool.copyView);
        vp->renderedWidth=s.width;vp->renderedHeight=s.height;
        vp->effectsHash=kine_vp_global_effects_hash(ctx);
        if(vp->historyView && vp->historyWarmup<2) ++vp->historyWarmup;
        vp->dirty=vp->historyView && vp->historyWarmup<2;vp->ready=true;++pool.renders;
    }
    if (!ctx->renderWorld) {
        pool.clearView->setBlendMode(View::BlendMode::TRANSLUCENT);
        pool.clearView->setScene(pool.presentScene);pool.clearView->setRenderTarget(ctx->renderTarget);
        pool.clearView->setViewport({0,0,uint32_t(ctx->width),uint32_t(ctx->height)});
        Renderer::ClearOptions clear{};clear.clear=false;clear.discard=false;
        ctx->renderer->setClearOptions(clear);ctx->renderer->render(pool.clearView);
    }
}
KINE_API bool Kine_Filament_Viewport_HasWork(KineFilamentContext *ctx) {
    if (ctx && ctx->viewportPool) {
        if (ctx->viewportPool->handles.empty()) return false;
        const auto hash=kine_vp_global_effects_hash(ctx);
        bool work=false;
        for (auto *vp : ctx->viewportPool->handles) {
            if(vp->requested) kine_vp_prepare_copy_effects(vp);
            if(vp->requested && vp->settings.postProcessing && vp->effectsHash!=hash) {vp->dirty=true;vp->historyWarmup=0;}
            if(vp->requested && vp->dirty && vp->page) work=true;
        }
        return work;
    }
    return false;
}
KINE_API void Kine_Filament_Viewport_RenderFrame(KineFilamentContext *ctx, float dt, bool world) {
    if (!ctx) return;
    (void)Kine_Filament_Viewport_HasWork(ctx); // also refresh effects when a world frame already forces rendering.
    ctx->renderWorld = world; Kine_Filament_RenderFrame(ctx, dt); ctx->renderWorld = true;
}
KINE_API void Kine_Filament_Viewport_Draw(KineFilamentViewport *vp, KineSkiaSurface *surface,
        float x, float y, float w, float h, float r, float g, float b, float opacity) {
    if (!vp || !vp->ready || !vp->page || !surface || opacity <= 0) return;
    auto &p = *vp->page;
    if (!p.image) {
#if KINE_FILAMENT_USE_VULKAN
        auto *compositor = reinterpret_cast<KineVulkanCompositor *>(vp->ctx->vulkanCompositor);
        KineSkiaVulkanImageInfo info{}; info.image = p.vkImage; info.format = VK_FORMAT_R8G8B8A8_UNORM;
        info.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        info.imageUsageFlags = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
        info.sampleCount = info.levelCount = 1; info.currentQueueFamily = VK_QUEUE_FAMILY_IGNORED;
        p.image = Kine_Skia_Image_WrapVulkan(static_cast<KineSkiaVulkanContext *>(Kine_VulkanCompositor_GetSkiaContext(compositor)), KINE_VP_ATLAS_SIZE, KINE_VP_ATLAS_SIZE, &info);
#else
        p.image = Kine_Skia_Image_WrapGL(surface, p.glTexture, KINE_VP_ATLAS_SIZE, KINE_VP_ATLAS_SIZE);
#endif
    }
    if (!p.image) return;
    int columns = KINE_VP_ATLAS_SIZE/p.cell;
    int sx = (vp->slot%columns)*p.cell, sy = (vp->slot/columns)*p.cell;
    // Skia image source rectangles use top-left coordinates on both backends.
    sy = KINE_VP_ATLAS_SIZE - sy - vp->renderedHeight;
    Kine_Skia_Surface_DrawImageScaled(surface, p.image, float(sx),float(sy),float(vp->renderedWidth),float(vp->renderedHeight),
        x,y,w,h,0,0,0,0,uint8_t(std::clamp(r,0.0f,1.0f)*255),uint8_t(std::clamp(g,0.0f,1.0f)*255),uint8_t(std::clamp(b,0.0f,1.0f)*255),255,uint8_t(std::clamp(opacity,0.0f,1.0f)*255));
}
KINE_API void Kine_Filament_Viewport_Stats(KineFilamentContext *ctx, uint32_t *handles, uint32_t *pages, uint64_t *renders) {
    auto *pool = ctx ? ctx->viewportPool : nullptr;
    if (handles) *handles = pool ? uint32_t(pool->handles.size()) : 0;
    if (pages) *pages = pool ? uint32_t(pool->pages.size()) : 0;
    if (renders) *renders = pool ? pool->renders : 0;
}
static void kine_viewport_shutdown(KineFilamentContext *ctx) {
    if (!ctx || !ctx->viewportPool) return;
    auto *pool = ctx->viewportPool;
    while (!pool->handles.empty()) {
        auto *vp = pool->handles.back();
        for (auto &c : vp->chunks) kine_vp_destroy_chunk(vp, c);
        vp->chunks.clear();
        kine_vp_release_scene(vp);
        vp->ctx = nullptr; vp->scene = nullptr; vp->page = nullptr; vp->ready = false;
        pool->handles.pop_back(); // owner releases this CPU tombstone on Destroy.
    }
    for (auto &entry : pool->meshes) Kine_Filament_DestroyMesh(ctx, entry.second);
    if (pool->presentScene) {
        pool->presentScene->remove(pool->presentEntity); ctx->engine->destroy(pool->presentEntity);
        EntityManager::get().destroy(pool->presentEntity); ctx->engine->destroy(pool->presentScene);
    }
    if (pool->presentMaterial) ctx->engine->destroy(pool->presentMaterial);
    if (pool->view) ctx->engine->destroy(pool->view);
    if (pool->copyView) ctx->engine->destroy(pool->copyView);
    if (pool->clearView) ctx->engine->destroy(pool->clearView);
    for (auto &p : pool->scratch) {
        p->clearScene->remove(p->clearEntity);ctx->engine->destroy(p->clearEntity);EntityManager::get().destroy(p->clearEntity);
        ctx->engine->destroy(p->clearScene);ctx->engine->destroy(p->clearMaterial);
        ctx->engine->destroy(p->target);ctx->engine->destroy(p->color);ctx->engine->destroy(p->depth);
    }
    if (pool->camera) ctx->engine->destroyCameraComponent(pool->cameraEntity);
    if (!pool->cameraEntity.isNull()) EntityManager::get().destroy(pool->cameraEntity);
    if (pool->shadowBoundsMesh) Kine_Filament_DestroyMesh(ctx,reinterpret_cast<KineFilamentMesh *>(pool->shadowBoundsMesh));
    if (pool->environment) ctx->engine->destroy(pool->environment);
    if (pool->material) ctx->engine->destroy(pool->material);
    if (pool->clearMaterial) ctx->engine->destroy(pool->clearMaterial);
    for (auto &p : pool->pages) kine_vp_free_page(ctx, *p);
    delete pool; ctx->viewportPool = nullptr;
}


