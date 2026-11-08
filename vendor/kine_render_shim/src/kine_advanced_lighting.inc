extern "C++" {
struct KineReflectionProbeState {
    View *view=nullptr;
    Entity cameraEntity;
    Camera *camera=nullptr;
    Texture *capture=nullptr,*filtered=nullptr,*depth=nullptr;
    RenderTarget *targets[6]={};
    IndirectLight *light=nullptr;
    std::unique_ptr<IBLPrefilterContext> filterContext;
    std::unique_ptr<IBLPrefilterContext::SpecularFilter> filter;
    int resolution=0;
    float nextCapture=0;
    float lastCapture=0;
    math::float3 lastPosition{1e10f};
    uint64_t captures=0;
};

struct KineSsgiState {
    Texture *color=nullptr,*depth=nullptr;
    Texture *depthColor=nullptr;
    RenderTarget *depthTarget=nullptr;
    View *depthView=nullptr;
    RenderTarget *target=nullptr;
    Scene *scene=nullptr;
    View *view=nullptr;
    Entity entity,cameraEntity;
    Camera *camera=nullptr;
    Material *material=nullptr;
    MaterialInstance *mi=nullptr;
    int width=0,height=0;
};

static math::float3 kine_probe_position(KineFilamentContext *ctx) {
    const float *v=ctx->advancedEffects[0].values;
    if (v[0]>0.5f && ctx->camera) {
        const math::float3 eye(ctx->camera->getModelMatrix()[3].xyz);
        math::float3 position=eye;float nearest=std::numeric_limits<float>::max();
        // Put the automatic probe inside the nearest metal object. Closed
        // surfaces cull their own backfaces during capture, avoiding self-reflection.
        for(const auto &[key,batch]:ctx->pendingBatches) {
            if(batch.lastQueuedFrame+1<ctx->batchFrame)continue;
            if(!key.mesh || key.materialKind!=KINE_MAT_DEFAULT || key.param2<0.5f)continue;
            for(const auto &transform:batch.transforms) {
                const math::float3 center=(transform*math::float4(key.mesh->localBounds.center,1.0f)).xyz;
                const float distance=length2(center-eye);
                if(distance<nearest){nearest=distance;position=center;}
            }
        }
        return position;
    }
    return {v[1],v[2],v[3]};
}

static void kine_destroy_reflection_probe(KineFilamentContext *ctx) {
    auto *p=ctx->reflectionProbe;if (!p) return;
    ctx->scene->setIndirectLight(ctx->indirectLight);
    if(p->light)ctx->engine->destroy(p->light);
    p->filter.reset();p->filterContext.reset();
    for(auto *t:p->targets)if(t)ctx->engine->destroy(t);
    if(p->capture)ctx->engine->destroy(p->capture);
    if(p->filtered)ctx->engine->destroy(p->filtered);
    if(p->depth)ctx->engine->destroy(p->depth);
    if(p->view)ctx->engine->destroy(p->view);
    if(!p->cameraEntity.isNull()){ctx->engine->destroyCameraComponent(p->cameraEntity);EntityManager::get().destroy(p->cameraEntity);}
    delete p;ctx->reflectionProbe=nullptr;
}

static void kine_capture_reflection_probe(KineFilamentContext *ctx) {
    if(!ctx->advancedEffects[0].enabled || !ctx->renderWorld || !ctx->skyTexture)return;
    const float *v=ctx->advancedEffects[0].values;
    int resolution=32;while(resolution<int(v[4]) && resolution<512)resolution*=2;
    if(ctx->reflectionProbe && ctx->reflectionProbe->resolution!=resolution)kine_destroy_reflection_probe(ctx);
    if(!ctx->reflectionProbe) {
        auto *p=ctx->reflectionProbe=new KineReflectionProbeState();p->resolution=resolution;
        p->cameraEntity=EntityManager::get().create();p->camera=ctx->engine->createCamera(p->cameraEntity);
        p->view=ctx->engine->createView();p->view->setScene(ctx->scene);p->view->setCamera(p->camera);
        p->view->setViewport({0,0,uint32_t(resolution),uint32_t(resolution)});
        p->view->setPostProcessingEnabled(false);
        p->view->setVisibleLayers(0xff,1);
        p->capture=Texture::Builder().width(resolution).height(resolution).levels(0xff)
            .sampler(Texture::Sampler::SAMPLER_CUBEMAP).format(Texture::InternalFormat::RGBA16F)
            .usage(Texture::Usage::COLOR_ATTACHMENT|Texture::Usage::SAMPLEABLE|Texture::Usage::GEN_MIPMAPPABLE).build(*ctx->engine);
        p->filtered=Texture::Builder().width(resolution).height(resolution).levels(5)
            .sampler(Texture::Sampler::SAMPLER_CUBEMAP).format(Texture::InternalFormat::RGBA16F)
            .usage(Texture::Usage::COLOR_ATTACHMENT|Texture::Usage::SAMPLEABLE).build(*ctx->engine);
        p->depth=Texture::Builder().width(resolution).height(resolution).format(Texture::InternalFormat::DEPTH32F)
            .usage(Texture::Usage::DEPTH_ATTACHMENT).build(*ctx->engine);
        for(int face=0;face<6;++face)p->targets[face]=RenderTarget::Builder()
            .texture(RenderTarget::AttachmentPoint::COLOR,p->capture).face(RenderTarget::AttachmentPoint::COLOR,Texture::CubemapFace(face))
            .texture(RenderTarget::AttachmentPoint::DEPTH,p->depth).build(*ctx->engine);
        p->filterContext=std::make_unique<IBLPrefilterContext>(*ctx->engine);
        IBLPrefilterContext::SpecularFilter::Config config;config.sampleCount=64;config.levelCount=5;
        p->filter=std::make_unique<IBLPrefilterContext::SpecularFilter>(*p->filterContext,config);
    }
    auto *p=ctx->reflectionProbe;
    const math::float3 position=kine_probe_position(ctx);
    const bool moved=length(position-p->lastPosition)>std::max(1.0f,v[8]*0.02f);
    // Sky animation or camera movement can dirty the probe every frame.
    // Even an early refresh needs a budget for the six cloud-bearing faces.
    const bool throttled=ctx->time-p->lastCapture<0.1f;
    const bool unchanged=ctx->time<p->nextCapture && !moved && !ctx->reflectionDirty;
    if(p->light && (throttled || unchanged)){ctx->scene->setIndirectLight(p->light);return;}
    p->lastCapture=ctx->time;
    p->nextCapture=ctx->time+std::max(v[5],0.1f);p->lastPosition=position;
    // Capture against the sky IBL, never our previous capture (which would
    // feed reflected energy back into itself on every update).
    ctx->scene->setIndirectLight(ctx->indirectLight);
    const math::float3 directions[6]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
    const math::float3 up[6]={{0,-1,0},{0,-1,0},{0,0,1},{0,0,-1},{0,-1,0},{0,-1,0}};
    Camera *mainCamera=ctx->camera;
    p->camera->setProjection(90.0,1.0,std::max(0.01f,v[7]),std::max(v[8],v[7]+1.0f),Camera::Fov::VERTICAL);
    p->camera->setExposure(mainCamera->getAperture(),mainCamera->getShutterSpeed(),mainCamera->getSensitivity());
    Renderer::ClearOptions clear;clear.clear=true;clear.discard=true;clear.clearColor=ctx->skyColor;
    ctx->renderer->setClearOptions(clear);
    for(int face=0;face<6;++face) {
        p->camera->lookAt(position,position+directions[face],up[face]);
        // Cloud geometry is camera-relative, so position it for each probe face.
        ctx->camera=p->camera;kine_update_cloud_layer(ctx);
        p->view->setRenderTarget(p->targets[face]);
        ctx->renderer->renderStandaloneView(p->view);
    }
    ctx->camera=mainCamera;kine_update_cloud_layer(ctx);
    (*p->filter)(p->capture,p->filtered);
    if(p->light)ctx->engine->destroy(p->light);
    math::float3 sh[9]={};sh[0]={ctx->skyColor.r,ctx->skyColor.g,ctx->skyColor.b};
    p->light=IndirectLight::Builder().reflections(p->filtered).irradiance(1,sh).intensity(15000.0f*std::max(0.0f,v[6])).build(*ctx->engine);
    ctx->scene->setIndirectLight(p->light);p->captures++;ctx->reflectionDirty=false;
}

static void kine_destroy_ssgi(KineFilamentContext *ctx) {
    auto *s=ctx->ssgi;if(!s)return;
    ctx->view->setRenderTarget(ctx->postSceneTarget ? ctx->postSceneTarget : ctx->renderTarget);
    const int width=ctx->viewportWidth>0?ctx->viewportWidth:ctx->width;
    const int height=ctx->viewportHeight>0?ctx->viewportHeight:ctx->height;
    const int y=std::clamp(ctx->height-ctx->viewportY-height,0,std::max(0,ctx->height-1));
    ctx->view->setViewport({ctx->postSceneTarget?0:ctx->viewportX,ctx->postSceneTarget?0:y,uint32_t(width),uint32_t(height)});
    if(s->scene && !s->entity.isNull())s->scene->remove(s->entity);
    if(!s->entity.isNull()){ctx->engine->destroy(s->entity);EntityManager::get().destroy(s->entity);}
    if(!s->cameraEntity.isNull()){ctx->engine->destroyCameraComponent(s->cameraEntity);EntityManager::get().destroy(s->cameraEntity);}
    if(s->view)ctx->engine->destroy(s->view);
    if(s->depthView)ctx->engine->destroy(s->depthView);
    if(s->scene)ctx->engine->destroy(s->scene);
    if(s->mi)ctx->engine->destroy(s->mi);
    if(s->material)ctx->engine->destroy(s->material);
    if(s->target)ctx->engine->destroy(s->target);
    if(s->depthTarget)ctx->engine->destroy(s->depthTarget);
    if(s->depthColor)ctx->engine->destroy(s->depthColor);
    if(s->color)ctx->engine->destroy(s->color);
    if(s->depth)ctx->engine->destroy(s->depth);
    delete s;ctx->ssgi=nullptr;
}

static void kine_prepare_ssgi(KineFilamentContext *ctx) {
    if(!ctx->advancedEffects[1].enabled){if(ctx->ssgi)kine_destroy_ssgi(ctx);return;}
    int width=ctx->viewportWidth>0?ctx->viewportWidth:ctx->width;
    int height=ctx->viewportHeight>0?ctx->viewportHeight:ctx->height;
    if(ctx->ssgi && (ctx->ssgi->width!=width || ctx->ssgi->height!=height))kine_destroy_ssgi(ctx);
    if(!ctx->ssgi) {
        auto *s=ctx->ssgi=new KineSsgiState();s->width=width;s->height=height;
        s->color=Texture::Builder().width(width).height(height).levels(1).format(Texture::InternalFormat::RGBA8)
            .usage(Texture::Usage::COLOR_ATTACHMENT|Texture::Usage::SAMPLEABLE).build(*ctx->engine);
        s->depth=Texture::Builder().width(width).height(height).levels(1).format(Texture::InternalFormat::DEPTH32F)
            .usage(Texture::Usage::DEPTH_ATTACHMENT|Texture::Usage::SAMPLEABLE).build(*ctx->engine);
        s->target=RenderTarget::Builder().texture(RenderTarget::AttachmentPoint::COLOR,s->color)
            .build(*ctx->engine);
        // Filament's post-processing path does not export its internal depth.
        // Render a matching, non-postprocessed geometry view for the GI gather.
        s->depthColor=Texture::Builder().width(width).height(height).format(Texture::InternalFormat::RGBA8)
            .usage(Texture::Usage::COLOR_ATTACHMENT).build(*ctx->engine);
        s->depthTarget=RenderTarget::Builder().texture(RenderTarget::AttachmentPoint::COLOR,s->depthColor)
            .texture(RenderTarget::AttachmentPoint::DEPTH,s->depth).build(*ctx->engine);
        s->depthView=ctx->engine->createView();s->depthView->setScene(ctx->scene);s->depthView->setCamera(ctx->camera);
        s->depthView->setViewport({0,0,uint32_t(width),uint32_t(height)});s->depthView->setRenderTarget(s->depthTarget);
        s->depthView->setPostProcessingEnabled(false);s->depthView->setShadowingEnabled(false);
        s->material=Material::Builder().package(KINE_SSGI_PACKAGE_KINE_SSGI_DATA,KINE_SSGI_PACKAGE_KINE_SSGI_SIZE).build(*ctx->engine);
        s->mi=s->material->createInstance();s->scene=ctx->engine->createScene();s->view=ctx->engine->createView();
        s->cameraEntity=EntityManager::get().create();s->camera=ctx->engine->createCamera(s->cameraEntity);
        s->entity=EntityManager::get().create();
        RenderableManager::Builder(1).boundingBox({{0,0,0},{1,1,0.1f}}).material(0,s->mi)
            .geometry(0,RenderableManager::PrimitiveType::TRIANGLES,ctx->postProcessQuadMesh->vb,ctx->postProcessQuadMesh->ib)
            .culling(false).castShadows(false).receiveShadows(false).build(*ctx->engine,s->entity);
        s->scene->addEntity(s->entity);s->view->setScene(s->scene);s->view->setCamera(s->camera);s->view->setPostProcessingEnabled(false);
    }
    auto *s=ctx->ssgi;const float *v=ctx->advancedEffects[1].values;
    TextureSampler linear(TextureSampler::MinFilter::LINEAR,TextureSampler::MagFilter::LINEAR,TextureSampler::WrapMode::CLAMP_TO_EDGE);
    TextureSampler nearest(TextureSampler::MinFilter::NEAREST,TextureSampler::MagFilter::NEAREST,TextureSampler::WrapMode::CLAMP_TO_EDGE);
    s->mi->setParameter("inputTexture",s->color,linear);s->mi->setParameter("depthTexture",s->depth,nearest);
    s->mi->setParameter("texel",math::float2{1.0f/width,1.0f/height});
    const auto projection=ctx->camera->getProjectionMatrix();
    s->mi->setParameter("focal",math::float2{float(projection[0].x),float(projection[1].y)});
    s->mi->setParameter("nearPlane",float(ctx->camera->getNear()));
    s->mi->setParameter("intensity",std::clamp(v[0],0.0f,5.0f));s->mi->setParameter("radius",std::max(v[1],0.1f));
    s->mi->setParameter("bias",std::max(v[2],0.001f));s->mi->setParameter("sampleCount",std::clamp(int(v[3]),4,64));
    s->mi->setParameter("maxDistance",std::max(v[4],1.0f));
    const bool custom=ctx->postProcessShader && ctx->postSceneTarget;
    s->view->setRenderTarget(custom?ctx->postSceneTarget:ctx->renderTarget);
    float l,r,b,t;
    if(custom){l=-0.5f;r=0.5f;b=-0.5f;t=0.5f;s->view->setViewport({0,0,uint32_t(width),uint32_t(height)});}
    else{kine_composite_quad_bounds(ctx,&l,&r,&b,&t);s->view->setViewport({0,0,uint32_t(ctx->width),uint32_t(ctx->height)});}
    s->camera->setProjection(Camera::Projection::ORTHO,l,r,b,t,0.1,10);s->camera->lookAt({0,0,1},{0,0,0},{0,1,0});
    ctx->view->setRenderTarget(s->target);ctx->view->setViewport({0,0,uint32_t(width),uint32_t(height)});
}

} // C++ helpers

KINE_API void Kine_Filament_SetAdvancedEffect(KineFilamentContext *ctx,int effect,bool enabled,const float *values,int count) {
    static const int counts[]={9,5,8,7,4,4,4};
    if(!ctx || !ctx->engine || !ctx->view || effect<0 || effect>=7 || !values || count!=counts[effect])return;
    auto &state=ctx->advancedEffects[effect];
    const bool changed=state.enabled!=enabled || !std::equal(values,values+count,state.values);
    state.enabled=enabled;std::copy(values,values+count,state.values);
    switch(effect) {
    case 0:
        if(!enabled)kine_destroy_reflection_probe(ctx);
        else if(changed && ctx->reflectionProbe)ctx->reflectionProbe->nextCapture=0;
        break;
    case 1: if(!enabled)kine_destroy_ssgi(ctx);break;
    case 2: if(enabled){auto o=ctx->view->getFogOptions();o.enabled=true;o.density=std::max(values[0],0.0f);o.distance=std::max(values[1],0.0f);
        o.height=values[2];o.heightFalloff=std::max(values[3],0.0f);o.maximumOpacity=std::clamp(values[4],0.0f,1.0f);o.color={values[5],values[6],values[7]};ctx->view->setFogOptions(o);}break;
    case 3: {auto o=ctx->view->getAmbientOcclusionOptions();o.ssct.enabled=enabled;
        if(enabled){o.enabled=true;o.ssct.intensity=values[0];o.ssct.shadowDistance=values[1];o.ssct.contactDistanceMax=values[2];o.ssct.lightConeRad=values[3];
            o.ssct.sampleCount=uint8_t(std::clamp(int(values[4]),1,255));o.ssct.rayCount=uint8_t(std::clamp(int(values[5]),1,32));
            o.ssct.depthBias=values[6];o.ssct.depthSlopeBias=values[6];o.ssct.lightDirection=-ctx->sunDirection;}ctx->view->setAmbientOcclusionOptions(o);break;}
    case 4: if(enabled){auto o=ctx->view->getTemporalAntiAliasingOptions();o.enabled=true;o.feedback=values[0];o.filterWidth=values[1];o.sharpness=values[2];o.lodBias=values[3];ctx->view->setTemporalAntiAliasingOptions(o);}break;
    case 5: if(enabled){auto o=ctx->view->getDynamicResolutionOptions();o.enabled=true;o.minScale={values[0],values[0]};o.maxScale={std::max(values[1],values[0]),std::max(values[1],values[0])};
        o.sharpness=values[2];o.quality=kine_quality_from_int(int(values[3]));ctx->view->setDynamicResolutionOptions(o);}break;
    case 6: {
        const int mode=enabled?std::clamp(int(values[0]),0,3):4;
        const float exposure=enabled?values[1]:0,temperature=enabled?values[2]:0,tint=enabled?values[3]:0;
        if(ctx->toneMappingMode==mode && ctx->advancedExposure==exposure && ctx->advancedTemperature==temperature && ctx->advancedTint==tint && (ctx->colorGrading || mode==4))break;
        ctx->toneMappingMode=mode;ctx->advancedExposure=exposure;ctx->advancedTemperature=temperature;ctx->advancedTint=tint;
        const float neutral[]={0,1,1,1,0,0};
        if(!enabled && std::equal(std::begin(neutral),std::end(neutral),ctx->gradingInputs))Kine_Filament_ClearColorGrading(ctx);
        else Kine_Filament_SetColorGrading(ctx,ctx->gradingInputs[0],ctx->gradingInputs[1],ctx->gradingInputs[2],ctx->gradingInputs[3],ctx->gradingInputs[4],ctx->gradingInputs[5]);break;
    }
    }
}

KINE_API bool Kine_Filament_GetAdvancedEffect(KineFilamentContext *ctx,int effect,bool *enabled,float *values,int capacity) {
    static const int counts[]={9,5,8,7,4,4,4};
    if(!ctx || effect<0 || effect>=7 || !enabled || !values || capacity<counts[effect])return false;
    *enabled=ctx->advancedEffects[effect].enabled;std::copy_n(ctx->advancedEffects[effect].values,counts[effect],values);return true;
}

KINE_API bool Kine_Filament_GetReflectionProbeRegion(KineFilamentContext *ctx,float *center,float *radius) {
    if(!ctx || !ctx->advancedEffects[0].enabled || !center || !radius)return false;
    auto p=kine_probe_position(ctx);center[0]=p.x;center[1]=p.y;center[2]=p.z;*radius=ctx->advancedEffects[0].values[8];return true;
}

KINE_API uint64_t Kine_Filament_GetReflectionProbeCaptureCount(KineFilamentContext *ctx) {
    return ctx && ctx->reflectionProbe?ctx->reflectionProbe->captures:0;
}
