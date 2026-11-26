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
    int nextFace=-1;
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
    View* sunView = nullptr;
    Camera* sunCamera = nullptr;
    Entity sunCameraEntity;
    Texture* sunDepth = nullptr;
    Texture* sunColorTarget = nullptr;
    RenderTarget* sunTarget = nullptr;
    Texture* ddgiFallback = nullptr;
};

static void kine_bind_ddgi(KineFilamentContext* ctx, KineSsgiState* state) {
    TextureSampler sampler(TextureSampler::MinFilter::LINEAR,
            TextureSampler::MagFilter::LINEAR,
            TextureSampler::WrapMode::CLAMP_TO_EDGE);
    const char* names[4] = {"ddgiL0", "ddgiL1X", "ddgiL1Y", "ddgiL1Z"};
    const auto* grid = ctx->ddgi;
    for (size_t i = 0; i < 4; ++i)
        state->mi->setParameter(names[i],
                grid ? grid->volumes[i] : state->ddgiFallback, sampler);
    if (grid) {
        state->mi->setParameter("ddgiOrigin", grid->origin);
        state->mi->setParameter("ddgiGridDimensions", math::float3{
                float(grid->count[0]), float(grid->count[1]), float(grid->count[2])});
        state->mi->setParameter("ddgiSpacing", grid->spacing);
    } else {
        state->mi->setParameter("ddgiOrigin", math::float3{});
        state->mi->setParameter("ddgiGridDimensions", math::float3{1.0f});
        state->mi->setParameter("ddgiSpacing", 1.0f);
    }
}

static math::float3 kine_probe_position(KineFilamentContext *ctx) {
    const float *v=ctx->advancedEffects[0].values;
    if (v[0]>0.5f && ctx->camera) {
        const math::float3 eye(ctx->camera->getModelMatrix()[3].xyz);
        math::float3 position=eye;float nearest=std::numeric_limits<float>::max();


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


    if(p->nextFace<0) {
        if(p->light && ctx->time<p->nextCapture) {ctx->scene->setIndirectLight(p->light);return;}
        p->lastPosition=kine_probe_position(ctx);
        p->lastCapture=ctx->time;
        p->nextCapture=ctx->time+std::max(v[5],0.1f);
        p->nextFace=0;
        ctx->reflectionDirty=false;
        p->camera->setProjection(90.0,1.0,std::max(0.01f,v[7]),std::max(v[8],v[7]+1.0f),Camera::Fov::VERTICAL);
        p->camera->setExposure(ctx->camera->getAperture(),ctx->camera->getShutterSpeed(),ctx->camera->getSensitivity());
    }


    ctx->scene->setIndirectLight(ctx->indirectLight);
    const math::float3 directions[6]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
    const math::float3 up[6]={{0,-1,0},{0,-1,0},{0,0,1},{0,0,-1},{0,-1,0},{0,-1,0}};
    Camera *mainCamera=ctx->camera;
    Renderer::ClearOptions clear;clear.clear=true;clear.discard=true;clear.clearColor=ctx->skyColor;
    ctx->renderer->setClearOptions(clear);
    const int endFace=p->light?std::min(6,p->nextFace+1):6;
    for(;p->nextFace<endFace;++p->nextFace) {
        const int face=p->nextFace;
        p->camera->lookAt(p->lastPosition,p->lastPosition+directions[face],up[face]);
        ctx->camera=p->camera;kine_update_cloud_layer(ctx);
        p->view->setRenderTarget(p->targets[face]);
        ++ctx->passStats.reflectionFaces;
        ctx->renderer->renderStandaloneView(p->view);
    }
    ctx->camera=mainCamera;kine_update_cloud_layer(ctx);
    if(p->nextFace<6) {ctx->scene->setIndirectLight(p->light);return;}
    p->nextFace=-1;
    (*p->filter)(p->capture,p->filtered);
    if(p->light)ctx->engine->destroy(p->light);
    const math::float3 irradiance = {ctx->skyColor.r, ctx->skyColor.g, ctx->skyColor.b};
    p->light = kine_build_environment_light(ctx, p->filtered, irradiance, 15000.0f*std::max(0.0f,v[6]));
    ctx->scene->setIndirectLight(p->light);p->captures++;
}

static void kine_destroy_sun_rays(KineFilamentContext* ctx, KineSsgiState* state) {
    if (state->sunView) {
        ctx->engine->destroy(state->sunView);
        state->sunView = nullptr;
    }
    if (state->sunTarget) ctx->engine->destroy(state->sunTarget);
    if (state->sunDepth) ctx->engine->destroy(state->sunDepth);
    if (state->sunColorTarget) ctx->engine->destroy(state->sunColorTarget);
    if (!state->sunCameraEntity.isNull()) {
        ctx->engine->destroyCameraComponent(state->sunCameraEntity);
        EntityManager::get().destroy(state->sunCameraEntity);
        state->sunCameraEntity = {};
    }
    state->sunTarget = nullptr;
    state->sunDepth = nullptr;
    state->sunColorTarget = nullptr;
    state->sunCamera = nullptr;
}

static bool kine_prepare_sun_rays(KineFilamentContext* ctx, KineSsgiState* state,
        const math::mat4& model) {
    const auto& rays = ctx->advancedEffects[15];
    if (!rays.enabled || rays.values[0] <= 0 || ctx->sunIntensity <= 0) {
        if (state->sunView) kine_destroy_sun_rays(ctx, state);
        return false;
    }
    if (!state->sunView) {
        constexpr uint32_t size = 512;
        state->sunDepth = Texture::Builder().width(size).height(size).levels(1)
            .format(Texture::InternalFormat::DEPTH32F)
            .usage(Texture::Usage::DEPTH_ATTACHMENT | Texture::Usage::SAMPLEABLE).build(*ctx->engine);
        state->sunColorTarget = Texture::Builder().width(size).height(size).levels(1)
            .format(Texture::InternalFormat::RGBA8)
            .usage(Texture::Usage::COLOR_ATTACHMENT).build(*ctx->engine);
        if (state->sunDepth && state->sunColorTarget) {
            state->sunTarget = RenderTarget::Builder()
                .texture(RenderTarget::AttachmentPoint::COLOR, state->sunColorTarget)
                .texture(RenderTarget::AttachmentPoint::DEPTH, state->sunDepth).build(*ctx->engine);
        }
        if (!state->sunTarget) {
            kine_destroy_sun_rays(ctx, state);
            return false;
        }
        state->sunCameraEntity = EntityManager::get().create();
        state->sunCamera = ctx->engine->createCamera(state->sunCameraEntity);
        state->sunView = ctx->engine->createView();
        state->sunView->setScene(ctx->scene);
        state->sunView->setCamera(state->sunCamera);
        state->sunView->setViewport({0, 0, size, size});
        state->sunView->setRenderTarget(state->sunTarget);
        state->sunView->setVisibleLayers(0xff, KINE_SUN_RAYS_CASTER_LAYER);
        state->sunView->setShadowingEnabled(false);
        state->sunView->setPostProcessingEnabled(false);
    }
    const auto sun = math::double3(ctx->sunDirection);
    const auto eye = model[3].xyz;
    const math::double3 up = std::abs(sun.y) > 0.95 ? math::double3{0, 0, 1} : math::double3{0, 1, 0};
    const float half = std::clamp(rays.values[3], 4.0f, 128.0f) * 1.05f;
    const float offset = half + 48;
    constexpr float near = 0.1f;
    const float far = offset + half + 1;
    state->sunCamera->lookAt(eye + sun * double(offset), eye, up);
    state->sunCamera->setProjection(Camera::Projection::ORTHO, -half, half, -half, half, near, far);
    const auto lightModel = state->sunCamera->getModelMatrix();
    state->mi->setParameter("sunRight", math::float3(lightModel[0].xyz) / (2 * half));
    state->mi->setParameter("sunUp", math::float3(lightModel[1].xyz) / (2 * half));
    state->mi->setParameter("sunDepthRange", math::float2{(far - offset) / (far - near), 1 / (far - near)});
    return true;
}

static void kine_destroy_ssgi(KineFilamentContext *ctx) {
    auto *s=ctx->ssgi;if(!s)return;
    if(ctx->postMaterialInstance && ctx->postSampleDepth) {
        TextureSampler nearest(TextureSampler::MinFilter::NEAREST,TextureSampler::MagFilter::NEAREST,TextureSampler::WrapMode::CLAMP_TO_EDGE);
        ctx->postMaterialInstance->setParameter("depthTexture",ctx->postSampleDepth,nearest);
    }
    ctx->view->setRenderTarget(ctx->postSceneTarget ? ctx->postSceneTarget : ctx->renderTarget);
    const int width=ctx->viewportWidth>0?ctx->viewportWidth:ctx->width;
    const int height=ctx->viewportHeight>0?ctx->viewportHeight:ctx->height;
    const int y=std::clamp(ctx->height-ctx->viewportY-height,0,std::max(0,ctx->height-1));
    ctx->view->setViewport({ctx->postSceneTarget?0:ctx->viewportX,ctx->postSceneTarget?0:y,uint32_t(width),uint32_t(height)});
    if(s->scene && !s->entity.isNull())s->scene->remove(s->entity);
    if(!s->entity.isNull()){ctx->engine->destroy(s->entity);EntityManager::get().destroy(s->entity);}
    if(!s->cameraEntity.isNull()){ctx->engine->destroyCameraComponent(s->cameraEntity);EntityManager::get().destroy(s->cameraEntity);}
    kine_destroy_sun_rays(ctx, s);
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
    if(s->ddgiFallback)ctx->engine->destroy(s->ddgiFallback);
    delete s;ctx->ssgi=nullptr;
}

static void kine_prepare_ssgi(KineFilamentContext *ctx) {
    const auto active = [ctx](int i) {
        return ctx->advancedEffects[i].enabled && ctx->advancedEffects[i].values[0] > 0.0f;
    };
    const bool cloudShadowActive = ctx->cloudCastShadows &&
            ctx->cloudEnabled && ctx->cloudShadowIntensity > 0.0f &&
            ctx->cloudCover > 0.0f && ctx->cloudDensity > 0.0f &&
            ctx->sunDirection.y > 0.08f;
    if (!active(1) && !active(7) && !active(8) && !active(9) && !active(15) &&
            !active(16) && !active(17) && !active(18) && !active(19) &&
            !cloudShadowActive) {
        if (ctx->ssgi) kine_destroy_ssgi(ctx);
        return;
    }
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


        s->depthColor=Texture::Builder().width(width).height(height).format(Texture::InternalFormat::RGBA8)
            .usage(Texture::Usage::COLOR_ATTACHMENT).build(*ctx->engine);
        s->depthTarget=RenderTarget::Builder().texture(RenderTarget::AttachmentPoint::COLOR,s->depthColor)
            .texture(RenderTarget::AttachmentPoint::DEPTH,s->depth).build(*ctx->engine);
        s->depthView=ctx->engine->createView();s->depthView->setScene(ctx->scene);s->depthView->setCamera(ctx->camera);
        s->depthView->setViewport({0,0,uint32_t(width),uint32_t(height)});s->depthView->setRenderTarget(s->depthTarget);
        s->depthView->setPostProcessingEnabled(false);s->depthView->setShadowingEnabled(false);
        s->ddgiFallback = Texture::Builder().width(1).height(1).depth(1).levels(1)
                .sampler(Texture::Sampler::SAMPLER_3D)
                .format(Texture::InternalFormat::RGBA16F)
                .usage(Texture::Usage::UPLOADABLE | Texture::Usage::SAMPLEABLE).build(*ctx->engine);
        if (s->ddgiFallback) {
            auto* pixels = static_cast<math::half*>(std::malloc(4 * sizeof(math::half)));
            if (pixels) {
                for (size_t i = 0; i < 4; ++i) pixels[i] = math::half(0.0f);
                Texture::PixelBufferDescriptor descriptor(pixels, 4 * sizeof(math::half),
                        Texture::Format::RGBA, Texture::Type::HALF,
                        [](void* data, size_t, void*) { std::free(data); });
                s->ddgiFallback->setImage(*ctx->engine, 0, 0, 0, 0, 1, 1, 1,
                        std::move(descriptor));
            }
        }
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
    s->mi->setParameter("intensity",ctx->advancedEffects[1].enabled?std::clamp(v[0],0.0f,5.0f):0.0f);s->mi->setParameter("radius",std::max(v[1],0.1f));
    s->mi->setParameter("bias",std::max(v[2],0.001f));s->mi->setParameter("sampleCount",std::clamp(int(v[3]),4,64));
    s->mi->setParameter("maxDistance",std::max(v[4],1.0f));
    s->mi->setParameter("giColorBleeding",std::clamp(v[5],0.0f,2.0f));
    s->mi->setParameter("giVisibilitySteps",std::clamp(int(v[6]),1,6));
    const auto &fog=ctx->advancedEffects[7];const float *f=fog.values;
    const auto model=ctx->camera->getModelMatrix();
    s->mi->setParameter("cameraPosition",math::float3(model[3].xyz));
    s->mi->setParameter("cameraRight",math::float3(model[0].xyz));
    s->mi->setParameter("cameraUp",math::float3(model[1].xyz));
    s->mi->setParameter("cameraForward",-math::float3(model[2].xyz));
    s->mi->setParameter("sunDirection",ctx->sunDirection);
    s->mi->setParameter("sunStrength",std::clamp(ctx->sunIntensity/100000.0f,0.0f,2.0f));
    const bool sunRays = kine_prepare_sun_rays(ctx, s, model);
    const float* r = ctx->advancedEffects[15].values;
    const auto& lights = ctx->engine->getLightManager();
    const auto sunLight = lights.getInstance(ctx->sunLight);
    s->mi->setParameter("sunTint", sunLight.isValid() ? lights.getColor(sunLight) : math::float3{1});
    s->mi->setParameter("sunOcclusion", sunRays ? s->sunDepth : s->depth, nearest);
    s->mi->setParameter("rayIntensity", sunRays ? r[0] : 0.0f);
    s->mi->setParameter("raySpread", r[1]);
    s->mi->setParameter("dustAmount", r[2]);
    s->mi->setParameter("rayDistance", r[3]);
    s->mi->setParameter("raySteps", std::clamp(int(r[4]), 8, 48));

    s->mi->setParameter("fogDensity",fog.enabled?f[0]:0.0f);
    s->mi->setParameter("fogHeight",f[1]);s->mi->setParameter("fogFalloff",f[2]);
    s->mi->setParameter("fogDistance",std::max(1.0f,f[3]));s->mi->setParameter("fogAnisotropy",f[4]);
    s->mi->setParameter("fogScattering",f[5]);s->mi->setParameter("fogNoise",f[6]);s->mi->setParameter("fogNoiseScale",f[7]);
    s->mi->setParameter("fogSteps",std::clamp(int(f[8]),4,64));s->mi->setParameter("fogColor",math::float3{f[9],f[10],f[11]});
    s->mi->setParameter("chromatic",ctx->advancedEffects[8].enabled?ctx->advancedEffects[8].values[0]:0.0f);
    s->mi->setParameter("grain",ctx->advancedEffects[9].enabled?ctx->advancedEffects[9].values[0]:0.0f);
    s->mi->setParameter("grainSize",std::max(1.0f,ctx->advancedEffects[9].values[1]));
    const auto& cavity = ctx->advancedEffects[16];
    s->mi->setParameter("cavityIntensity", cavity.enabled ? std::clamp(cavity.values[0], 0.0f, 4.0f) : 0.0f);
    s->mi->setParameter("cavityRadius", std::clamp(cavity.values[1], 0.01f, 5.0f));
    s->mi->setParameter("cavityBias", std::clamp(cavity.values[2], 0.0f, 1.0f));
    s->mi->setParameter("cavityMaxDistance", std::max(cavity.values[3], 1.0f));
    const auto& outline = ctx->advancedEffects[17];
    s->mi->setParameter("outlineIntensity", outline.enabled ? std::clamp(outline.values[0], 0.0f, 1.0f) : 0.0f);
    s->mi->setParameter("outlineThickness", std::clamp(outline.values[1], 0.5f, 5.0f));
    s->mi->setParameter("outlineDepthThreshold", std::clamp(outline.values[2], 0.001f, 1.0f));
    s->mi->setParameter("outlineNormalThreshold", std::clamp(outline.values[3], 0.0f, 1.0f));
    const auto& emissiveGi = ctx->advancedEffects[18];
    s->mi->setParameter("emissiveGiIntensity", emissiveGi.enabled ?
            std::clamp(emissiveGi.values[0], 0.0f, 5.0f) : 0.0f);
    s->mi->setParameter("emissiveGiRadius", std::clamp(emissiveGi.values[1], 0.1f, 30.0f));
    s->mi->setParameter("emissiveGiThreshold", std::clamp(emissiveGi.values[2], 0.0f, 1.0f));
    s->mi->setParameter("emissiveGiFalloff", std::clamp(emissiveGi.values[3], 0.0f, 8.0f));
    s->mi->setParameter("emissiveGiMaxDistance", std::max(emissiveGi.values[4], 1.0f));
    s->mi->setParameter("emissiveGiSamples", std::clamp(int(emissiveGi.values[5]), 4, 32));
    const auto& ddgi = ctx->advancedEffects[19];
    s->mi->setParameter("ddgiIntensity", ddgi.enabled && ctx->ddgi ?
            std::clamp(ddgi.values[0], 0.0f, 5.0f) : 0.0f);
    if (s->ddgiFallback) kine_bind_ddgi(ctx, s);
    float cloudShadowIntensity = 0.0f;
    Texture* cloudShadowNoise = s->ddgiFallback;
    if (ctx->cloudCastShadows && ctx->cloudEnabled && ctx->cloudVolumeTextures[0] &&
            ctx->cloudCover > 0.0f && ctx->cloudDensity > 0.0f &&
            ctx->sunDirection.y > 0.08f && ctx->sunIntensity > 0.0f) {
        cloudShadowIntensity = ctx->cloudShadowIntensity;
        cloudShadowNoise = ctx->cloudVolumeTextures[0];
    }
    if (cloudShadowNoise) {
        TextureSampler sampler(TextureSampler::MinFilter::LINEAR_MIPMAP_LINEAR,
                TextureSampler::MagFilter::LINEAR, TextureSampler::WrapMode::REPEAT);
        s->mi->setParameter("cloudShadowNoise", cloudShadowNoise, sampler);
    }
    s->mi->setParameter("cloudShadowIntensity", cloudShadowIntensity);
    s->mi->setParameter("cloudShadowScale", ctx->cloudShadowScale);
    s->mi->setParameter("cloudShadowSpeed", ctx->cloudShadowSpeed);
    s->mi->setParameter("cloudShadowSoftness", ctx->cloudShadowSoftness);
    s->mi->setParameter("cloudShadowMaxDistance", ctx->cloudShadowMaxDistance);
    s->mi->setParameter("cloudShadowHeight", ctx->cloudHeight);
    s->mi->setParameter("cloudShadowThickness", ctx->cloudThickness);
    s->mi->setParameter("cloudShadowCover", ctx->cloudCover);
    s->mi->setParameter("cloudShadowDensity", ctx->cloudDensity);
    s->mi->setParameter("effectTime",ctx->time);
    const bool custom=ctx->postProcessShader && ctx->postSceneTarget;
    s->view->setRenderTarget(custom?ctx->postSceneTarget:ctx->renderTarget);
    float l,right,b,t;
    if(custom){l=-0.5f;right=0.5f;b=-0.5f;t=0.5f;s->view->setViewport({0,0,uint32_t(width),uint32_t(height)});}
    else{kine_composite_quad_bounds(ctx,&l,&right,&b,&t);s->view->setViewport({0,0,uint32_t(ctx->width),uint32_t(ctx->height)});}
    s->camera->setProjection(Camera::Projection::ORTHO,l,right,b,t,0.1,10);s->camera->lookAt({0,0,1},{0,0,0},{0,1,0});
    ctx->view->setRenderTarget(s->target);ctx->view->setViewport({0,0,uint32_t(width),uint32_t(height)});
}

}

static void kine_update_environment_irradiance(KineFilamentContext* ctx,
        IndirectLight*& light, Texture* reflections, math::float3 irradiance) {
    if (!light) return;
    auto* replacement = kine_build_environment_light(ctx, reflections, irradiance, light->getIntensity());
    if (!replacement) return;
    if (ctx->scene->getIndirectLight() == light) ctx->scene->setIndirectLight(replacement);
    ctx->engine->destroy(light);
    light = replacement;
}

static constexpr int kine_advanced_effect_counts[] = {9, 7, 8, 7, 4, 4, 4, 12, 1, 2, 1, 8, 9, 5, 9, 5, 4, 4, 6, 9};

KINE_API void Kine_Filament_SetAdvancedEffect(KineFilamentContext *ctx,int effect,bool enabled,const float *values,int count) {
    if(!ctx || !ctx->engine || !ctx->view || effect<0 ||
            effect>=int(std::size(kine_advanced_effect_counts)) || !values)return;
    const bool legacySsgi = effect == 1 && count == 5;
    if (count != kine_advanced_effect_counts[effect] && !legacySsgi) return;
    float previousSsgi[7]{};
    if (legacySsgi) {
        std::copy_n(values, 5, previousSsgi);
        const auto& configured = ctx->advancedEffects[1];
        previousSsgi[5] = configured.values[6] > 0.0f ? configured.values[5] : 1.0f;
        previousSsgi[6] = configured.values[6] > 0.0f ? configured.values[6] : 3.0f;
        values = previousSsgi;
        count = 7;
    }
    const float previousSkylight = kine_skylight_multiplier(ctx);
    auto &state=ctx->advancedEffects[effect];
    const bool wasEnabled=state.enabled;
    const bool changed=wasEnabled!=enabled || !std::equal(values,values+count,state.values);
    state.enabled=enabled;std::copy(values,values+count,state.values);
    switch(effect) {
    case 0:
        if(!enabled)kine_destroy_reflection_probe(ctx);
        else if(changed && ctx->reflectionProbe) {ctx->reflectionProbe->nextCapture=0;ctx->reflectionProbe->nextFace=-1;}
        break;
    case 1: case 7: case 8: case 9: case 15: case 16: case 17: case 18: case 19: break;
    case 2: if(enabled){auto o=ctx->view->getFogOptions();o.enabled=true;o.density=std::max(values[0],0.0f);o.distance=std::max(values[1],0.0f);
        o.height=values[2];o.heightFalloff=std::max(values[3],0.0f);o.maximumOpacity=std::clamp(values[4],0.0f,1.0f);o.color={values[5],values[6],values[7]};ctx->view->setFogOptions(o);}
        else if(wasEnabled){auto o=ctx->view->getFogOptions();o.enabled=false;ctx->view->setFogOptions(o);}break;
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
    case 10: {
        if (kine_skylight_multiplier(ctx) == previousSkylight) break;
        kine_update_environment_irradiance(ctx, ctx->indirectLight, ctx->skyTexture, ctx->skyIrradiance);
        if (auto* probe = ctx->reflectionProbe) {
            const math::float3 irradiance = {ctx->skyColor.r, ctx->skyColor.g, ctx->skyColor.b};
            kine_update_environment_irradiance(ctx, probe->light, probe->filtered, irradiance);
        }
        break;
    }
    case 11: {
        if (!enabled && !changed) break;
        auto bloom = ctx->view->getBloomOptions();
        BloomOptions defaults;
        if (enabled) bloom.lensFlare = true;
        bloom.starburst = enabled ? values[0] != 0 : defaults.starburst;
        bloom.chromaticAberration = enabled ? values[1] : defaults.chromaticAberration;
        bloom.ghostCount = enabled ? uint8_t(values[2]) : defaults.ghostCount;
        bloom.ghostSpacing = enabled ? values[3] : defaults.ghostSpacing;
        bloom.ghostThreshold = enabled ? values[4] : defaults.ghostThreshold;
        bloom.haloThickness = enabled ? values[5] : defaults.haloThickness;
        bloom.haloRadius = enabled ? values[6] : defaults.haloRadius;
        bloom.haloThreshold = enabled ? values[7] : defaults.haloThreshold;
        ctx->view->setBloomOptions(bloom);
        break;
    }
    case 12: {
        if (!changed) break;
        const float neutral[] = {0, 1, 1, 1, 0, 0};
        if (!enabled && std::equal(std::begin(neutral), std::end(neutral), ctx->gradingInputs)) {
            Kine_Filament_ClearColorGrading(ctx);
        } else {
            const auto* grade = ctx->gradingInputs;
            Kine_Filament_SetColorGrading(ctx, grade[0], grade[1], grade[2], grade[3], grade[4], grade[5]);
        }
        break;
    }
    case 13: {
        if (!changed || ctx->sunLight.isNull()) break;
        auto& lights = ctx->engine->getLightManager();
        auto sun = lights.getInstance(ctx->sunLight);
        if (!sun.isValid()) break;
        const math::float3 color = enabled
            ? math::float3{values[2], values[3], values[4]}
            : math::float3{1.0f, 0.98f, 0.95f};
        lights.setColor(sun, Color::toLinear<ACCURATE>(color));
        break;
    }
    case 14: {
        if (!changed) break;
        auto ao = ctx->view->getAmbientOcclusionOptions();
        const AmbientOcclusionOptions defaults;
        ao.resolution = enabled && values[0] != 0 ? 1.0f : defaults.resolution;
        ao.bentNormals = enabled && values[1] != 0;
        ao.bias = enabled ? values[2] : defaults.bias;
        ao.bilateralThreshold = enabled ? values[3] : defaults.bilateralThreshold;
        ao.lowPassFilter = enabled ? kine_quality_from_int(int(values[4])) : defaults.lowPassFilter;
        ao.upsampling = enabled ? kine_quality_from_int(int(values[5])) : defaults.upsampling;
        ao.gtao.sampleSliceCount = enabled ?
                uint8_t(std::clamp(int(values[6]), 1, 16)) : defaults.gtao.sampleSliceCount;
        ao.gtao.sampleStepsPerSlice = enabled ?
                uint8_t(std::clamp(int(values[7]), 1, 8)) : defaults.gtao.sampleStepsPerSlice;
        ao.gtao.useVisibilityBitmasks = enabled && values[8] != 0;
        if (ao.gtao.useVisibilityBitmasks) ao.bentNormals = false;
        ctx->view->setAmbientOcclusionOptions(ao);
        break;
    }

    }
}

KINE_API bool Kine_Filament_GetAdvancedEffect(KineFilamentContext *ctx,int effect,bool *enabled,float *values,int capacity) {
    if(!ctx || effect<0 || effect>=int(std::size(kine_advanced_effect_counts)) ||
            !enabled || !values || capacity < (effect == 1 ? 5 : kine_advanced_effect_counts[effect]))return false;
    *enabled=ctx->advancedEffects[effect].enabled;
    std::copy_n(ctx->advancedEffects[effect].values,
            std::min(capacity,kine_advanced_effect_counts[effect]),values);
    return true;
}

KINE_API bool Kine_Filament_GetReflectionProbeRegion(KineFilamentContext *ctx,float *center,float *radius) {
    if(!ctx || !ctx->advancedEffects[0].enabled || !center || !radius)return false;
    const auto *probe=ctx->reflectionProbe;
    const auto p=probe && probe->light && (probe->nextFace>=0 || ctx->time<probe->nextCapture) ? probe->lastPosition : kine_probe_position(ctx);center[0]=p.x;center[1]=p.y;center[2]=p.z;*radius=ctx->advancedEffects[0].values[8];return true;
}

KINE_API uint64_t Kine_Filament_GetReflectionProbeCaptureCount(KineFilamentContext *ctx) {
    return ctx && ctx->reflectionProbe?ctx->reflectionProbe->captures:0;
}
