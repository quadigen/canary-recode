// Experimental desktop OpenXR backend. Included by kine_filament_shim.cpp.
// The desktop renderer owns the Vulkan device; OpenXR owns its swapchain images.
#if KINE_XR_COMPILED
struct KineXREye {
    uint32_t width = 0, height = 0, acquired = 0;
    XrSwapchain swapchain = XR_NULL_HANDLE;
    std::vector<XrSwapchainImageVulkanKHR> images;
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    backend::Platform::ExternalImageHandle external;
    Texture *color = nullptr, *depth = nullptr;
    RenderTarget *target = nullptr;
    View *view = nullptr;
    Camera *camera = nullptr;
    Entity cameraEntity;
    Entity cloudEntity;
    MaterialInstance *cloudMI = nullptr;
    bool acquiredImage = false, waited = false;
};
#define KINE_XR_CORE(X) \
    X(xrDestroyInstance) X(xrGetSystem) X(xrGetSystemProperties) X(xrCreateSession) X(xrDestroySession) \
    X(xrEnumerateViewConfigurationViews) X(xrEnumerateEnvironmentBlendModes) \
    X(xrCreateReferenceSpace) X(xrDestroySpace) X(xrLocateSpace) \
    X(xrEnumerateSwapchainFormats) X(xrCreateSwapchain) X(xrDestroySwapchain) \
    X(xrEnumerateSwapchainImages) X(xrAcquireSwapchainImage) X(xrWaitSwapchainImage) \
    X(xrReleaseSwapchainImage) X(xrPollEvent) X(xrBeginSession) X(xrEndSession) \
    X(xrWaitFrame) X(xrBeginFrame) X(xrLocateViews) X(xrEndFrame) \
    X(xrStringToPath) X(xrCreateActionSet) X(xrDestroyActionSet) X(xrCreateAction) \
    X(xrSuggestInteractionProfileBindings) X(xrAttachSessionActionSets) \
    X(xrCreateActionSpace) X(xrSyncActions) X(xrGetActionStatePose) \
    X(xrGetActionStateBoolean) X(xrGetActionStateFloat) X(xrGetActionStateVector2f) \
    X(xrApplyHapticFeedback) X(xrStopHapticFeedback)
struct KineXR {
    void *loader = nullptr;
    PFN_xrGetInstanceProcAddr getProc = nullptr;
#define XR_MEMBER(name) PFN_##name name = nullptr;
    KINE_XR_CORE(XR_MEMBER)
#undef XR_MEMBER
    XrInstance instance = XR_NULL_HANDLE;
    XrSystemId system = XR_NULL_SYSTEM_ID;
    XrSession session = XR_NULL_HANDLE;
    XrSpace local = XR_NULL_HANDLE, head = XR_NULL_HANDLE, floor = XR_NULL_HANDLE;
    XrSpace hands[2]{}, aimSpaces[2]{};
    XrActionSet actions = XR_NULL_HANDLE;
    XrAction grip = XR_NULL_HANDLE, aim = XR_NULL_HANDLE;
    XrAction trigger = XR_NULL_HANDLE, select = XR_NULL_HANDLE;
    XrAction squeeze = XR_NULL_HANDLE, squeezeClick = XR_NULL_HANDLE;
    XrAction stick = XR_NULL_HANDLE, haptic = XR_NULL_HANDLE;
    KineXRControllerState controllers[2]{};
    XrPath handPaths[2]{};
    XrSessionState state = XR_SESSION_STATE_UNKNOWN;
    XrEnvironmentBlendMode blend = XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
    XrFrameState frame{XR_TYPE_FRAME_STATE};
    XrView views[2]{{XR_TYPE_VIEW}, {XR_TYPE_VIEW}};
    KineXREye eyes[2];
    KineXREye panel;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkFence copyFence = VK_NULL_HANDLE;
    bool panelEnabled = false, panelReady = false, panelMirror = false;
    KineSkiaSurface *panelSurface = nullptr;
    VkImageUsageFlags panelUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    uint32_t panelWidth = 0, panelHeight = 0;
    float poses[4][12]{};
    bool valid[4]{}, running = false, frameBegun = false, rendered = false, failed = false;
    bool loggedIdle = false, loggedStereo = false, loggedPanel = false;
    uint32_t measuredFrames = 0;
    std::chrono::steady_clock::time_point measurementStart{};
    double waitMs = 0, copyMs = 0;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkCommandBuffer command = VK_NULL_HANDLE;
};
static bool kine_xr_ok(XrResult r, const char *what) {
    if (XR_SUCCEEDED(r)) return true;
    fprintf(stderr, "[KineXR] %s failed (%d)\n", what, int(r));
    return false;
}
// This implementation is included inside the shim's extern "C" block.
// The typed loader helper is internal C++ and must override that linkage.
extern "C++" {
template<class T> static bool kine_xr_proc(KineXR &x, const char *name, T &out) {
    PFN_xrVoidFunction fn = nullptr;
    if (!kine_xr_ok(x.getProc(x.instance, name, &fn), name) || !fn) return false;
    out = reinterpret_cast<T>(fn);
    return true;
}
} // extern "C++"
static void kine_xr_pose(const XrPosef &p, float *a) {
    const float x=p.orientation.x,y=p.orientation.y,z=p.orientation.z,w=p.orientation.w;
    a[0]=p.position.x; a[1]=p.position.y; a[2]=p.position.z;
    a[3]=1-2*(y*y+z*z); a[4]=2*(x*y-z*w); a[5]=2*(x*z+y*w);
    a[6]=2*(x*y+z*w); a[7]=1-2*(x*x+z*z); a[8]=2*(y*z-x*w);
    a[9]=2*(x*z-y*w); a[10]=2*(y*z+x*w); a[11]=1-2*(x*x+y*y);
}
static math::mat4 kine_xr_matrix(const XrPosef &p) {
    float a[12]; kine_xr_pose(p,a);
    return math::mat4{math::double4{a[3],a[6],a[9],0}, math::double4{a[4],a[7],a[10],0},
                      math::double4{a[5],a[8],a[11],0}, math::double4{a[0],a[1],a[2],1}};
}
static void kine_xr_destroy(KineFilamentContext *ctx) {
    if (!ctx || !ctx->xr) return;
    auto *x = ctx->xr; ctx->xr = nullptr;
    if (ctx->engine) ctx->engine->flushAndWait();
    if (x->panelSurface) Kine_Skia_Surface_Flush(x->panelSurface);
    if (x->queue) vkQueueWaitIdle(x->queue);
    for (auto &e : x->eyes) {
        if (e.view) ctx->engine->destroy(e.view);
        if (!e.cloudEntity.isNull()) {ctx->scene->remove(e.cloudEntity);ctx->engine->destroy(e.cloudEntity);EntityManager::get().destroy(e.cloudEntity);}
        if (e.cloudMI) ctx->engine->destroy(e.cloudMI);
        if (e.camera) {ctx->engine->destroyCameraComponent(e.cameraEntity); EntityManager::get().destroy(e.cameraEntity);}
        if (e.target) ctx->engine->destroy(e.target);
        if (e.depth) ctx->engine->destroy(e.depth);
        if (e.color) ctx->engine->destroy(e.color);
    }
    if (ctx->engine) ctx->engine->flushAndWait();
    // A runtime failure can interrupt acquire/wait. Release any image that
    // can still be waited successfully before destroying its swapchain.
    auto releasePending=[&](KineXREye &e){
        if(!e.acquiredImage || !e.swapchain || !x->xrWaitSwapchainImage || !x->xrReleaseSwapchainImage)return;
        if(!e.waited){
            XrSwapchainImageWaitInfo wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};wait.timeout=0;
            e.waited=x->xrWaitSwapchainImage(e.swapchain,&wait)==XR_SUCCESS;
        }
        if(e.waited){
            XrSwapchainImageReleaseInfo release{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
            (void)x->xrReleaseSwapchainImage(e.swapchain,&release);
        }
        e.acquiredImage=false;e.waited=false;
    };
    for (auto &e : x->eyes) {
        releasePending(e);
        e.external.clear();
        if (e.image) vkDestroyImage(x->device,e.image,nullptr);
        if (e.memory) vkFreeMemory(x->device,e.memory,nullptr);
        if (e.swapchain && x->xrDestroySwapchain) x->xrDestroySwapchain(e.swapchain);
    }
    if(x->panelSurface){Kine_Skia_Surface_Destroy(x->panelSurface);x->panelSurface=nullptr;}
    // Drop cached Skia image views before the runtime frees its swapchain.
    if(x->panel.swapchain && !x->panelMirror && ctx->vulkanCompositor){
        auto *skia=static_cast<KineSkiaVulkanContext*>(Kine_VulkanCompositor_GetSkiaContext(static_cast<KineVulkanCompositor*>(ctx->vulkanCompositor)));
        if(skia)Kine_Skia_Vulkan_PurgeResources(skia);
    }
    releasePending(x->panel);
    if (x->panel.swapchain && x->xrDestroySwapchain) x->xrDestroySwapchain(x->panel.swapchain);
    if (x->copyFence) vkDestroyFence(x->device,x->copyFence,nullptr);
    if (x->pool) vkDestroyCommandPool(x->device,x->pool,nullptr);
    for (auto h : x->hands) if (h && x->xrDestroySpace) x->xrDestroySpace(h);
    for (auto h : x->aimSpaces) if (h && x->xrDestroySpace) x->xrDestroySpace(h);
    if (x->head && x->xrDestroySpace) x->xrDestroySpace(x->head);
    if (x->floor && x->xrDestroySpace) x->xrDestroySpace(x->floor);
    if (x->local && x->xrDestroySpace) x->xrDestroySpace(x->local);
    if (x->session && x->xrDestroySession) x->xrDestroySession(x->session);
    if (x->actions && x->xrDestroyActionSet) x->xrDestroyActionSet(x->actions);
    if (x->instance && x->xrDestroyInstance) x->xrDestroyInstance(x->instance);
    if (x->loader) dlclose(x->loader);
    delete x;
}
static bool kine_xr_eye(KineFilamentContext *ctx, KineXR &x, KineXREye &e, const XrViewConfigurationView &cfg, VkPhysicalDevice physical) {
    float scale=1.0f;
    if(const char *value=std::getenv("KINE_VR_SCALE")){
        char *end=nullptr;float parsed=std::strtof(value,&end);
        if(end!=value && *end=='\0' && std::isfinite(parsed))scale=std::clamp(parsed,0.4f,1.0f);
    }
    e.width=std::max(1u,uint32_t(cfg.recommendedImageRectWidth*scale));
    e.height=std::max(1u,uint32_t(cfg.recommendedImageRectHeight*scale));
    fprintf(stderr,"[KineXR] Eye target %ux%u (scale %.2f)\n",e.width,e.height,scale);
    XrSwapchainCreateInfo sc{XR_TYPE_SWAPCHAIN_CREATE_INFO};
    sc.usageFlags=XR_SWAPCHAIN_USAGE_TRANSFER_DST_BIT | XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT;
    sc.format=VK_FORMAT_R8G8B8A8_UNORM; sc.sampleCount=1; sc.width=e.width; sc.height=e.height;
    sc.faceCount=sc.arraySize=sc.mipCount=1;
    if (!kine_xr_ok(x.xrCreateSwapchain(x.session,&sc,&e.swapchain),"create swapchain")) return false;
    uint32_t count=0;
    if (!kine_xr_ok(x.xrEnumerateSwapchainImages(e.swapchain,0,&count,nullptr),"enumerate images") || !count) return false;
    e.images.resize(count,{XR_TYPE_SWAPCHAIN_IMAGE_VULKAN_KHR});
    if (!kine_xr_ok(x.xrEnumerateSwapchainImages(e.swapchain,count,&count,reinterpret_cast<XrSwapchainImageBaseHeader*>(e.images.data())),"get images")) return false;
    // Intermediate images let Filament retain its own layout tracking; OpenXR
    // images are only touched between acquire/wait and release.
    VkImageCreateInfo im{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    im.imageType=VK_IMAGE_TYPE_2D; im.format=VK_FORMAT_R8G8B8A8_UNORM;
    im.extent={e.width,e.height,1}; im.mipLevels=im.arrayLayers=1;
    im.samples=VK_SAMPLE_COUNT_1_BIT; im.tiling=VK_IMAGE_TILING_OPTIMAL;
    im.usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_SAMPLED_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    im.sharingMode=VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateImage(x.device,&im,nullptr,&e.image)!=VK_SUCCESS) return false;
    VkMemoryRequirements req{}; vkGetImageMemoryRequirements(x.device,e.image,&req);
    VkPhysicalDeviceMemoryProperties mem{}; vkGetPhysicalDeviceMemoryProperties(physical,&mem);
    uint32_t type=UINT32_MAX;
    for(uint32_t i=0;i<mem.memoryTypeCount;++i) if((req.memoryTypeBits&(1u<<i)) && (mem.memoryTypes[i].propertyFlags&VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)){type=i;break;}
    if(type==UINT32_MAX) return false;
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; alloc.allocationSize=req.size;alloc.memoryTypeIndex=type;
    if(vkAllocateMemory(x.device,&alloc,nullptr,&e.memory)!=VK_SUCCESS || vkBindImageMemory(x.device,e.image,e.memory,0)!=VK_SUCCESS) return false;
    auto *external=new KineViewportExternalImage(); external->image=e.image; external->width=e.width; external->height=e.height;
    e.external=backend::Platform::ExternalImageHandle(external);
    e.color=Texture::Builder().width(e.width).height(e.height).levels(1).format(Texture::InternalFormat::RGBA8)
        .usage(Texture::Usage::COLOR_ATTACHMENT|Texture::Usage::SAMPLEABLE|Texture::Usage::BLIT_SRC).external().build(*ctx->engine);
    if(!e.color) return false;
    e.color->setExternalImage(*ctx->engine,e.external);
    e.depth=Texture::Builder().width(e.width).height(e.height).levels(1).format(Texture::InternalFormat::DEPTH32F)
        .usage(Texture::Usage::DEPTH_ATTACHMENT|Texture::Usage::SAMPLEABLE).build(*ctx->engine);
    if(!e.depth) return false;
    e.target=RenderTarget::Builder().texture(RenderTarget::AttachmentPoint::COLOR,e.color)
        .texture(RenderTarget::AttachmentPoint::DEPTH,e.depth).build(*ctx->engine);
    if(!e.target) return false;
    e.cameraEntity=EntityManager::get().create(); e.camera=ctx->engine->createCamera(e.cameraEntity); e.view=ctx->engine->createView();
    if(!e.camera || !e.view) return false;
    e.view->setCamera(e.camera);e.view->setScene(ctx->scene);e.view->setRenderTarget(e.target);
    e.view->setViewport({0,0,e.width,e.height});
    e.view->setPostProcessingEnabled(false); // no desktop post-process in the eyes
    e.view->setVisibleLayers(0xff,0xff);
    return true;
}
static bool kine_xr_panel_init(KineXR &x) {
    XrSystemProperties props{XR_TYPE_SYSTEM_PROPERTIES};
    if(!kine_xr_ok(x.xrGetSystemProperties(x.instance,x.system,&props),"UI panel system properties") ||
       props.graphicsProperties.maxLayerCount<2)return false;
    auto &p=x.panel;
    p.width=std::min(1024u,props.graphicsProperties.maxSwapchainImageWidth);
    p.height=std::min(1024u,props.graphicsProperties.maxSwapchainImageHeight);
    if(!p.width||!p.height)return false;
    XrSwapchainCreateInfo sc{XR_TYPE_SWAPCHAIN_CREATE_INFO};
    sc.usageFlags=XR_SWAPCHAIN_USAGE_TRANSFER_DST_BIT|XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT;
    if(!x.panelMirror){
        sc.usageFlags|=XR_SWAPCHAIN_USAGE_TRANSFER_SRC_BIT|XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
        x.panelUsage|=VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_SAMPLED_BIT;
    }
    sc.format=VK_FORMAT_R8G8B8A8_UNORM;sc.sampleCount=1;sc.width=p.width;sc.height=p.height;
    sc.faceCount=sc.arraySize=sc.mipCount=1;
    if(!kine_xr_ok(x.xrCreateSwapchain(x.session,&sc,&p.swapchain),"create UI panel"))return false;
    uint32_t n=0;
    if(!kine_xr_ok(x.xrEnumerateSwapchainImages(p.swapchain,0,&n,nullptr),"panel images")||!n)return false;
    p.images.resize(n,{XR_TYPE_SWAPCHAIN_IMAGE_VULKAN_KHR});
    return kine_xr_ok(x.xrEnumerateSwapchainImages(p.swapchain,n,&n,reinterpret_cast<XrSwapchainImageBaseHeader*>(p.images.data())),"get panel images");
}
static bool kine_xr_actions(KineXR &x) {
    XrActionSetCreateInfo set{XR_TYPE_ACTION_SET_CREATE_INFO};
    strcpy(set.actionSetName,"kinemium");strcpy(set.localizedActionSetName,"Kinemium");
    if(!kine_xr_ok(x.xrCreateActionSet(x.instance,&set,&x.actions),"action set")) return false;
    const char *hands[]={"/user/hand/left","/user/hand/right"};
    for(int i=0;i<2;++i) if(!kine_xr_ok(x.xrStringToPath(x.instance,hands[i],&x.handPaths[i]),"hand path")) return false;
    XrActionCreateInfo action{XR_TYPE_ACTION_CREATE_INFO};action.actionType=XR_ACTION_TYPE_POSE_INPUT;
    strcpy(action.actionName,"grip_pose");strcpy(action.localizedActionName,"Grip pose");
    action.countSubactionPaths=2;action.subactionPaths=x.handPaths;
    if(!kine_xr_ok(x.xrCreateAction(x.actions,&action,&x.grip),"grip action")) return false;
    auto makeAction = [&](XrAction &out, XrActionType type, const char *name, const char *label) {
        XrActionCreateInfo info{XR_TYPE_ACTION_CREATE_INFO};
        info.actionType=type; info.countSubactionPaths=2; info.subactionPaths=x.handPaths;
        snprintf(info.actionName,sizeof(info.actionName),"%s",name);
        snprintf(info.localizedActionName,sizeof(info.localizedActionName),"%s",label);
        return kine_xr_ok(x.xrCreateAction(x.actions,&info,&out),name);
    };
    if(!makeAction(x.aim,XR_ACTION_TYPE_POSE_INPUT,"aim_pose","Aim pose") ||
       !makeAction(x.trigger,XR_ACTION_TYPE_FLOAT_INPUT,"trigger","Trigger") ||
       !makeAction(x.select,XR_ACTION_TYPE_BOOLEAN_INPUT,"select","Select") ||
       !makeAction(x.squeeze,XR_ACTION_TYPE_FLOAT_INPUT,"squeeze","Squeeze") ||
       !makeAction(x.squeezeClick,XR_ACTION_TYPE_BOOLEAN_INPUT,"squeeze_click","Squeeze button") ||
       !makeAction(x.stick,XR_ACTION_TYPE_VECTOR2F_INPUT,"stick","Thumbstick or trackpad") ||
       !makeAction(x.haptic,XR_ACTION_TYPE_VIBRATION_OUTPUT,"haptic","Haptic feedback")) return false;
    struct Profile {
        const char *name, *trigger, *select, *squeeze, *squeezeClick, *stick;
    };
    const Profile profiles[]={
        {"/interaction_profiles/khr/simple_controller",nullptr,"/input/select/click",nullptr,nullptr,nullptr},
        {"/interaction_profiles/oculus/touch_controller","/input/trigger/value",nullptr,"/input/squeeze/value",nullptr,"/input/thumbstick"},
        {"/interaction_profiles/valve/index_controller","/input/trigger/value",nullptr,"/input/squeeze/value",nullptr,"/input/thumbstick"},
        {"/interaction_profiles/htc/vive_controller","/input/trigger/value",nullptr,nullptr,"/input/squeeze/click","/input/trackpad"},
        {"/interaction_profiles/microsoft/motion_controller","/input/trigger/value",nullptr,nullptr,"/input/squeeze/click","/input/thumbstick"}
    };
    for(const auto &profile:profiles){
        XrInteractionProfileSuggestedBinding suggest{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
        if(XR_FAILED(x.xrStringToPath(x.instance,profile.name,&suggest.interactionProfile)))continue;
        std::vector<XrActionSuggestedBinding> bindings;
        for(int i=0;i<2;++i){
            auto bind=[&](XrAction a,const char *component){
                if(!component)return;
                XrPath path=XR_NULL_PATH;
                auto full=std::string(hands[i])+component;
                if(XR_SUCCEEDED(x.xrStringToPath(x.instance,full.c_str(),&path)))
                    bindings.push_back({a,path});
            };
            bind(x.grip,"/input/grip/pose");bind(x.aim,"/input/aim/pose");
            bind(x.trigger,profile.trigger);bind(x.select,profile.select);
            bind(x.squeeze,profile.squeeze);bind(x.squeezeClick,profile.squeezeClick);
            bind(x.stick,profile.stick);bind(x.haptic,"/output/haptic");
        }
        suggest.countSuggestedBindings=uint32_t(bindings.size());suggest.suggestedBindings=bindings.data();
        if(XR_FAILED(x.xrSuggestInteractionProfileBindings(x.instance,&suggest)))
            fprintf(stderr,"[KineXR] Controller bindings unavailable for %s\n",profile.name);
    }
    XrSessionActionSetsAttachInfo attach{XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};attach.countActionSets=1;attach.actionSets=&x.actions;
    if(!kine_xr_ok(x.xrAttachSessionActionSets(x.session,&attach),"attach actions"))return false;
    for(int i=0;i<2;++i){
        XrActionSpaceCreateInfo space{XR_TYPE_ACTION_SPACE_CREATE_INFO};space.action=x.grip;space.subactionPath=x.handPaths[i];space.poseInActionSpace.orientation.w=1;
        if(!kine_xr_ok(x.xrCreateActionSpace(x.session,&space,&x.hands[i]),"hand space"))return false;
        space.action=x.aim;
        if(!kine_xr_ok(x.xrCreateActionSpace(x.session,&space,&x.aimSpaces[i]),"aim space"))return false;
    }
    return true;
}
static bool kine_xr_init(KineFilamentContext *ctx) {
    if(!ctx->useFilamentOwnedCompositor || !ctx->engine || !ctx->vulkanPlatform) return false;
    auto *platform=static_cast<KineFilamentCompositorVulkanPlatform*>(ctx->vulkanPlatform.get());
    if(!platform->xrVulkanReady())return false;
    auto &x=*(ctx->xr=new KineXR);
    x.loader=dlopen("libopenxr_loader.so.1",RTLD_NOW|RTLD_LOCAL);
    if(!x.loader){fprintf(stderr,"[KineXR] OpenXR loader not installed\n");return false;}
    x.getProc=reinterpret_cast<PFN_xrGetInstanceProcAddr>(dlsym(x.loader,"xrGetInstanceProcAddr"));
    if(!x.getProc)return false;
    PFN_xrCreateInstance create=nullptr;
    if(!kine_xr_proc(x,"xrCreateInstance",create))return false;
    const char *extensions[]={XR_KHR_VULKAN_ENABLE_EXTENSION_NAME};
    XrInstanceCreateInfo ii{XR_TYPE_INSTANCE_CREATE_INFO};
    strcpy(ii.applicationInfo.applicationName,"Kinemium");strcpy(ii.applicationInfo.engineName,"Kinemium");
    ii.applicationInfo.applicationVersion=ii.applicationInfo.engineVersion=1;
    ii.applicationInfo.apiVersion=XR_MAKE_VERSION(1,0,0);ii.enabledExtensionCount=1;ii.enabledExtensionNames=extensions;
    if(!kine_xr_ok(create(&ii,&x.instance),"create instance"))return false;
#define XR_LOAD(name) if(!kine_xr_proc(x,#name,x.name))return false;
    KINE_XR_CORE(XR_LOAD)
#undef XR_LOAD
    XrSystemGetInfo si{XR_TYPE_SYSTEM_GET_INFO};si.formFactor=XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    if(!kine_xr_ok(x.xrGetSystem(x.instance,&si,&x.system),"get HMD"))return false;
    KineFilamentVulkanBackend b{};
    if(!Kine_Filament_GetVulkanBackend(ctx,&b))return false;
    PFN_xrGetVulkanGraphicsRequirementsKHR requirements=nullptr;
    PFN_xrGetVulkanGraphicsDeviceKHR gpu=nullptr;
    if(!kine_xr_proc(x,"xrGetVulkanGraphicsRequirementsKHR",requirements)||!kine_xr_proc(x,"xrGetVulkanGraphicsDeviceKHR",gpu))return false;
    XrGraphicsRequirementsVulkanKHR gr{XR_TYPE_GRAPHICS_REQUIREMENTS_VULKAN_KHR};
    if(!kine_xr_ok(requirements(x.instance,x.system,&gr),"Vulkan requirements"))return false;
    VkInstance instance=reinterpret_cast<VkInstance>(b.instance);
    VkPhysicalDevice physical=reinterpret_cast<VkPhysicalDevice>(b.physicalDevice), requiredGpu=VK_NULL_HANDLE;
    if(!kine_xr_ok(gpu(x.instance,x.system,instance,&requiredGpu),"OpenXR Vulkan GPU")||physical!=requiredGpu){
        fprintf(stderr,"[KineXR] OpenXR and Filament must use the same Vulkan GPU\n");return false;
    }
    const uint32_t vkApi=platform->xrVulkanApiVersion();
    const XrVersion api=XR_MAKE_VERSION(VK_API_VERSION_MAJOR(vkApi),VK_API_VERSION_MINOR(vkApi),VK_API_VERSION_PATCH(vkApi));
    if(api<gr.minApiVersionSupported || api>gr.maxApiVersionSupported){fprintf(stderr,"[KineXR] Filament Vulkan API version outside runtime range\n");return false;}
    x.device=reinterpret_cast<VkDevice>(b.device);x.queue=reinterpret_cast<VkQueue>(b.queue);x.physical=physical;
    VkQueue queue0=VK_NULL_HANDLE;vkGetDeviceQueue(x.device,b.graphicsQueueFamilyIndex,0,&queue0);
    if(queue0!=x.queue){fprintf(stderr,"[KineXR] unexpected Filament graphics queue index\n");return false;}
    XrGraphicsBindingVulkanKHR binding{XR_TYPE_GRAPHICS_BINDING_VULKAN_KHR};
    binding.instance=instance;binding.physicalDevice=physical;binding.device=x.device;binding.queueFamilyIndex=b.graphicsQueueFamilyIndex;binding.queueIndex=0;
    XrSessionCreateInfo session{XR_TYPE_SESSION_CREATE_INFO};session.systemId=x.system;session.next=&binding;
    if(!kine_xr_ok(x.xrCreateSession(x.instance,&session,&x.session),"create session"))return false;
    XrReferenceSpaceCreateInfo ref{XR_TYPE_REFERENCE_SPACE_CREATE_INFO};ref.poseInReferenceSpace.orientation.w=1;
    ref.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_LOCAL;
    if(!kine_xr_ok(x.xrCreateReferenceSpace(x.session,&ref,&x.local),"local space"))return false;
    ref.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_VIEW;
    if(!kine_xr_ok(x.xrCreateReferenceSpace(x.session,&ref,&x.head),"head space"))return false;
    ref.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_STAGE;(void)x.xrCreateReferenceSpace(x.session,&ref,&x.floor);
    if(!kine_xr_actions(x))return false;
    uint32_t count=0;
    if(!kine_xr_ok(x.xrEnumerateEnvironmentBlendModes(x.instance,x.system,XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,0,&count,nullptr),"blend modes")||!count)return false;
    std::vector<XrEnvironmentBlendMode> modes(count);
    if(!kine_xr_ok(x.xrEnumerateEnvironmentBlendModes(x.instance,x.system,XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,count,&count,modes.data()),"blend modes"))return false;
    if(std::find(modes.begin(),modes.end(),XR_ENVIRONMENT_BLEND_MODE_OPAQUE)==modes.end())return false;
    if(!kine_xr_ok(x.xrEnumerateViewConfigurationViews(x.instance,x.system,XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,0,&count,nullptr),"view count")||count!=2)return false;
    XrViewConfigurationView cfg[2]{{XR_TYPE_VIEW_CONFIGURATION_VIEW},{XR_TYPE_VIEW_CONFIGURATION_VIEW}};
    if(!kine_xr_ok(x.xrEnumerateViewConfigurationViews(x.instance,x.system,XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,2,&count,cfg),"views"))return false;
    if(!kine_xr_ok(x.xrEnumerateSwapchainFormats(x.session,0,&count,nullptr),"format count")||!count)return false;
    std::vector<int64_t> formats(count);
    if(!kine_xr_ok(x.xrEnumerateSwapchainFormats(x.session,count,&count,formats.data()),"formats"))return false;
    if(std::find(formats.begin(),formats.end(),VK_FORMAT_R8G8B8A8_UNORM)==formats.end()){fprintf(stderr,"[KineXR] runtime has no RGBA8 UNORM swapchain\n");return false;}
    VkCommandPoolCreateInfo pool{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};pool.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;pool.queueFamilyIndex=b.graphicsQueueFamilyIndex;
    if(vkCreateCommandPool(x.device,&pool,nullptr,&x.pool)!=VK_SUCCESS)return false;
    VkCommandBufferAllocateInfo cmd{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};cmd.commandPool=x.pool;cmd.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY;cmd.commandBufferCount=1;
    if(vkAllocateCommandBuffers(x.device,&cmd,&x.command)!=VK_SUCCESS)return false;
    VkFenceCreateInfo fence{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    if(vkCreateFence(x.device,&fence,nullptr,&x.copyFence)!=VK_SUCCESS)return false;
    for(int i=0;i<2;++i)if(!kine_xr_eye(ctx,x,x.eyes[i],cfg[i],physical))return false;
    // Keep the stable no-panel mode available. 1/native renders Skia directly;
    // mirror is the older desktop screenshot-style layer.
    if(const char *ui=std::getenv("KINE_VR_UI");ui &&
       (std::strcmp(ui,"1")==0 || std::strcmp(ui,"native")==0 || std::strcmp(ui,"mirror")==0)){
        x.panelMirror=std::strcmp(ui,"mirror")==0;
        x.panelEnabled=kine_xr_panel_init(x);
        fprintf(stderr,"[KineXR] %s UI panel %s\n",x.panelMirror?"Desktop mirror":"Native Skia",x.panelEnabled?"enabled":"unavailable");
    }
    fprintf(stderr,"[KineXR] OpenXR session created\n");
    return true;
}
KINE_API void Kine_Filament_XR_Poll(KineFilamentContext *ctx) {
    if(!ctx)return;
    if(!ctx->xrAttempted){
        ctx->xrAttempted=true;
        const char *enable=getenv("KINE_VR");
        if(enable && strcmp(enable,"1")==0 && !kine_xr_init(ctx)){fprintf(stderr,"[KineXR] initialization failed; continuing in desktop mode\n");kine_xr_destroy(ctx);}
    }
    auto *x=ctx->xr;if(!x)return;
    if(x->failed){kine_xr_destroy(ctx);return;}
    XrEventDataBuffer event{XR_TYPE_EVENT_DATA_BUFFER};
    XrResult result;
    while((result=x->xrPollEvent(x->instance,&event))==XR_SUCCESS){
        if(event.type==XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED){
            auto &change=*reinterpret_cast<XrEventDataSessionStateChanged*>(&event);x->state=change.state;
            fprintf(stderr,"[KineXR] Session state: %d\n",int(x->state));
            if(x->state==XR_SESSION_STATE_READY && !x->running){
                XrSessionBeginInfo begin{XR_TYPE_SESSION_BEGIN_INFO};begin.primaryViewConfigurationType=XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
                x->running=kine_xr_ok(x->xrBeginSession(x->session,&begin),"begin session");
                if(!x->running)x->failed=true;
            }else if(x->state==XR_SESSION_STATE_STOPPING && x->running){
                (void)x->xrEndSession(x->session);x->running=false;
                for(auto &v:x->valid)v=false;
                for(auto &c:x->controllers)c={};
            }else if(x->state==XR_SESSION_STATE_EXITING || x->state==XR_SESSION_STATE_LOSS_PENDING)x->failed=true;
        }else if(event.type==XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING)x->failed=true;
        event={XR_TYPE_EVENT_DATA_BUFFER};
    }
    if(XR_FAILED(result))x->failed=true;
    if(x->failed)kine_xr_destroy(ctx);
}
KINE_API bool Kine_Filament_XR_Active(KineFilamentContext *ctx){return ctx && ctx->xr && ctx->xr->running && !ctx->xr->failed;}
KINE_API bool Kine_Filament_XR_Available(KineFilamentContext *ctx){return ctx && ctx->xr && !ctx->xr->failed;}
KINE_API bool Kine_Filament_XR_GetPose(KineFilamentContext *ctx,int index,float *out){
    if(!out || index<0 || index>=4 || !Kine_Filament_XR_Active(ctx) || !ctx->xr->valid[index])return false;
    memcpy(out,ctx->xr->poses[index],12*sizeof(float));return true;
}
KINE_API bool Kine_Filament_XR_GetControllerState(KineFilamentContext *ctx,int hand,KineXRControllerState *out){
    if(!out)return false;
    *out={};
    if(hand<0 || hand>=2 || !Kine_Filament_XR_Active(ctx) ||
       ctx->xr->state!=XR_SESSION_STATE_FOCUSED)return false;
    *out=ctx->xr->controllers[hand];return out->active_mask!=0;
}
KINE_API bool Kine_Filament_XR_SetHaptic(KineFilamentContext *ctx,int hand,float amplitude,float seconds,float frequency){
    if(hand<0 || hand>=2 || !Kine_Filament_XR_Active(ctx) ||
       ctx->xr->state!=XR_SESSION_STATE_FOCUSED ||
       !std::isfinite(amplitude) || !std::isfinite(seconds) || !std::isfinite(frequency) ||
       amplitude<0 || amplitude>1 || seconds<0 || seconds>10 || frequency<0)return false;
    auto &x=*ctx->xr;
    XrHapticActionInfo info{XR_TYPE_HAPTIC_ACTION_INFO};info.action=x.haptic;info.subactionPath=x.handPaths[hand];
    if(amplitude==0 || seconds==0)return x.xrStopHapticFeedback(x.session,&info)==XR_SUCCESS;
    XrHapticVibration vibration{XR_TYPE_HAPTIC_VIBRATION};
    vibration.amplitude=amplitude;vibration.frequency=frequency;
    vibration.duration=std::max<XrDuration>(1,XrDuration(double(seconds)*1000000000.0));
    return x.xrApplyHapticFeedback(x.session,&info,reinterpret_cast<const XrHapticBaseHeader*>(&vibration))==XR_SUCCESS;
}
static void kine_xr_read_controller(KineXR &x,int hand,bool synced){
    auto &c=x.controllers[hand];c={};
    if(!synced)return;
    XrActionStateGetInfo get{XR_TYPE_ACTION_STATE_GET_INFO};get.subactionPath=x.handPaths[hand];
    auto readFloat=[&](XrAction action,float &value,uint32_t bit){
        get.action=action;XrActionStateFloat s{XR_TYPE_ACTION_STATE_FLOAT};
        if(XR_SUCCEEDED(x.xrGetActionStateFloat(x.session,&get,&s)) && s.isActive){
            value=std::clamp(s.currentState,0.0f,1.0f);c.active_mask|=bit;return true;
        }
        return false;
    };
    auto readClick=[&](XrAction action,float &value,uint32_t bit){
        get.action=action;XrActionStateBoolean s{XR_TYPE_ACTION_STATE_BOOLEAN};
        if(XR_SUCCEEDED(x.xrGetActionStateBoolean(x.session,&get,&s)) && s.isActive){
            value=s.currentState?1.0f:0.0f;c.active_mask|=bit;
        }
    };
    if(!readFloat(x.trigger,c.trigger,1u))readClick(x.select,c.trigger,1u);
    if(!readFloat(x.squeeze,c.grip,2u))readClick(x.squeezeClick,c.grip,2u);
    get.action=x.stick;XrActionStateVector2f s{XR_TYPE_ACTION_STATE_VECTOR2F};
    if(XR_SUCCEEDED(x.xrGetActionStateVector2f(x.session,&get,&s)) && s.isActive){
        c.stick_x=s.currentState.x;c.stick_y=s.currentState.y;c.active_mask|=4u;
    }
}
static void kine_xr_locate(KineXR &x,int index,XrSpace space){
    x.valid[index]=false;if(!space)return;
    XrSpaceLocation location{XR_TYPE_SPACE_LOCATION};
    if(XR_SUCCEEDED(x.xrLocateSpace(space,x.local,x.frame.predictedDisplayTime,&location)) &&
       (location.locationFlags&(XR_SPACE_LOCATION_POSITION_VALID_BIT|XR_SPACE_LOCATION_ORIENTATION_VALID_BIT))==(XR_SPACE_LOCATION_POSITION_VALID_BIT|XR_SPACE_LOCATION_ORIENTATION_VALID_BIT)){
        kine_xr_pose(location.pose,x.poses[index]);x.valid[index]=true;
    }
}
static void kine_xr_begin(KineFilamentContext *ctx){
    if(!Kine_Filament_XR_Active(ctx))return;
    auto &x=*ctx->xr;
    if(x.frameBegun)return;
    x.frame={XR_TYPE_FRAME_STATE};x.rendered=false;x.panelReady=false;
    XrFrameWaitInfo wait{XR_TYPE_FRAME_WAIT_INFO};XrFrameBeginInfo begin{XR_TYPE_FRAME_BEGIN_INFO};
    const auto waitStart=std::chrono::steady_clock::now();
    XrResult waited=x.xrWaitFrame(x.session,&wait,&x.frame);
    x.waitMs+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-waitStart).count();
    if(waited!=XR_SUCCESS){
        fprintf(stderr,"[KineXR] xrWaitFrame returned %d\n",int(waited));x.failed=true;return;
    }
    XrResult begun=x.xrBeginFrame(x.session,&begin);
    if(begun!=XR_SUCCESS && begun!=XR_FRAME_DISCARDED){
        fprintf(stderr,"[KineXR] xrBeginFrame returned %d\n",int(begun));x.failed=true;return;
    }
    x.frameBegun=true;
    kine_xr_locate(x,0,x.head);kine_xr_locate(x,3,x.floor);
    XrActiveActionSet active{x.actions,XR_NULL_PATH};XrActionsSyncInfo sync{XR_TYPE_ACTIONS_SYNC_INFO};sync.countActiveActionSets=1;sync.activeActionSets=&active;
    bool synced=x.xrSyncActions(x.session,&sync)==XR_SUCCESS;
    for(int i=0;i<2;++i){
        XrActionStateGetInfo get{XR_TYPE_ACTION_STATE_GET_INFO};get.action=x.grip;get.subactionPath=x.handPaths[i];
        XrActionStatePose state{XR_TYPE_ACTION_STATE_POSE};
        if(synced && XR_SUCCEEDED(x.xrGetActionStatePose(x.session,&get,&state)) && state.isActive)kine_xr_locate(x,i+1,x.hands[i]);
        else x.valid[i+1]=false;
        kine_xr_read_controller(x,i,synced);
    }
}
static bool kine_xr_prepare_cloud(KineFilamentContext *ctx,KineXREye &e){
    if(!ctx->cloudEnabled || !kine_ensure_cloud_layer(ctx))return false;
    if(!e.cloudMI){
        e.cloudMI=ctx->cloudMaterial->createInstance();
        if(!e.cloudMI)return false;
        e.cloudEntity=EntityManager::get().create();
        RenderableManager::Builder(1)
            .boundingBox({{-1.0f,-1.0f,-1.0f},{1.0f,1.0f,1.0f}})
            .material(0,e.cloudMI)
            .geometry(0,RenderableManager::PrimitiveType::TRIANGLES,ctx->cloudMesh->vb,ctx->cloudMesh->ib)
            .culling(false).castShadows(false).receiveShadows(false)
            .build(*ctx->engine,e.cloudEntity);
    }
    kine_update_cloud_for_camera(ctx,e.camera,e.cloudEntity,e.cloudMI);
    return true;
}
static void kine_xr_render(KineFilamentContext *ctx){
    auto *xp=ctx->xr;if(!xp || !xp->frameBegun || !xp->frame.shouldRender || !ctx->renderWorld)return;
    auto &x=*xp;
    XrViewLocateInfo locate{XR_TYPE_VIEW_LOCATE_INFO};locate.viewConfigurationType=XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;locate.displayTime=x.frame.predictedDisplayTime;locate.space=x.local;
    XrViewState state{XR_TYPE_VIEW_STATE};uint32_t count=0;
    if(!kine_xr_ok(x.xrLocateViews(x.session,&locate,&state,2,&count,x.views),"locate views")||count!=2||
       (state.viewStateFlags&(XR_VIEW_STATE_POSITION_VALID_BIT|XR_VIEW_STATE_ORIENTATION_VALID_BIT))!=(XR_VIEW_STATE_POSITION_VALID_BIT|XR_VIEW_STATE_ORIENTATION_VALID_BIT))return;
    for(auto &e:x.eyes){
        XrSwapchainImageAcquireInfo acquire{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};XrSwapchainImageWaitInfo wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};wait.timeout=XR_INFINITE_DURATION;
        if(!kine_xr_ok(x.xrAcquireSwapchainImage(e.swapchain,&acquire,&e.acquired),"acquire eye")){x.failed=true;return;}
        e.acquiredImage=true;
        XrResult result=x.xrWaitSwapchainImage(e.swapchain,&wait);
        if(result!=XR_SUCCESS){fprintf(stderr,"[KineXR] wait eye returned %d\n",int(result));x.failed=true;return;}
        e.waited=true;
        if(e.acquired>=e.images.size()){fprintf(stderr,"[KineXR] invalid eye image index\n");x.failed=true;return;}
    }
    const auto base=ctx->camera->getModelMatrix();const double near=ctx->nearPlane,far=ctx->farPlane;
    Renderer::ClearOptions clear{};clear.clear=true;clear.discard=true;clear.clearColor=ctx->skyColor;clear.clearColor[3]=1.0f;
    ctx->renderer->setClearOptions(clear);
    // The desktop proxy has already been drawn. Each eye needs its own
    // transform and material instance; never expose the other eye's quad.
    const bool desktopCloud=ctx->cloudInScene;
    if(desktopCloud)ctx->scene->remove(ctx->cloudEntity);
    for(int i=0;i<2;++i){
        auto &e=x.eyes[i];auto &v=x.views[i];
        e.camera->setModelMatrix(base*kine_xr_matrix(v.pose));
        e.camera->setProjection(Camera::Projection::PERSPECTIVE,near*std::tan(v.fov.angleLeft),near*std::tan(v.fov.angleRight),near*std::tan(v.fov.angleDown),near*std::tan(v.fov.angleUp),near,far);
        const bool cloud=kine_xr_prepare_cloud(ctx,e);
        if(cloud)ctx->scene->addEntity(e.cloudEntity);
        ctx->renderer->render(e.view);
        if(cloud)ctx->scene->remove(e.cloudEntity);
    }
    if(desktopCloud)ctx->scene->addEntity(ctx->cloudEntity);
    x.rendered=true;
}
static void kine_xr_barrier(VkCommandBuffer cmd,VkImage image,VkImageLayout oldLayout,VkImageLayout newLayout,VkAccessFlags src,VkAccessFlags dst,VkPipelineStageFlags srcStage,VkPipelineStageFlags dstStage){
    VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};b.oldLayout=oldLayout;b.newLayout=newLayout;b.srcAccessMask=src;b.dstAccessMask=dst;
    b.srcQueueFamilyIndex=b.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED;b.image=image;b.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};
    vkCmdPipelineBarrier(cmd,srcStage,dstStage,0,0,nullptr,0,nullptr,1,&b);
}
// Called on the Skia render thread, after the Filament backend handoff.
KINE_API KineSkiaSurface *Kine_Filament_XR_BeginUI(KineFilamentContext *ctx,int width,int height,int *outWidth,int *outHeight){
    if(!ctx || !ctx->xr || !outWidth || !outHeight || width<=0 || height<=0)return nullptr;
    auto &x=*ctx->xr;auto &p=x.panel;
    if(!x.panelEnabled || x.panelMirror || !x.frameBegun || !x.rendered || x.failed || p.acquiredImage)return nullptr;
    auto *compositor=static_cast<KineVulkanCompositor*>(ctx->vulkanCompositor);
    auto *skia=static_cast<KineSkiaVulkanContext*>(Kine_VulkanCompositor_GetSkiaContext(compositor));
    if(!skia)return nullptr;
    XrSwapchainImageAcquireInfo acquire{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
    XrSwapchainImageWaitInfo wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};wait.timeout=XR_INFINITE_DURATION;
    if(x.xrAcquireSwapchainImage(p.swapchain,&acquire,&p.acquired)!=XR_SUCCESS)return nullptr;
    p.acquiredImage=true;
    if(x.xrWaitSwapchainImage(p.swapchain,&wait)!=XR_SUCCESS){x.failed=true;return nullptr;}
    p.waited=true;
    if(p.acquired>=p.images.size()){x.failed=true;return nullptr;}
    const float scale=std::min(float(p.width)/float(width),float(p.height)/float(height));
    x.panelWidth=std::min(p.width,std::max(1u,uint32_t(width*scale)));
    x.panelHeight=std::min(p.height,std::max(1u,uint32_t(height*scale)));
    KineSkiaVulkanImageInfo info{};info.image=p.images[p.acquired].image;
    info.format=VK_FORMAT_R8G8B8A8_UNORM;info.imageLayout=VK_IMAGE_LAYOUT_UNDEFINED;
    info.imageTiling=VK_IMAGE_TILING_OPTIMAL;info.imageUsageFlags=x.panelUsage;
    info.sampleCount=info.levelCount=1;info.currentQueueFamily=VK_QUEUE_FAMILY_IGNORED;
    x.panelSurface=Kine_Skia_Surface_CreateVulkanRenderTarget(skia,int(p.width),int(p.height),&info);
    if(!x.panelSurface){fprintf(stderr,"[KineXR] Skia could not wrap UI image\n");x.panelEnabled=false;return nullptr;}
    Kine_Skia_Surface_Clear(x.panelSurface,0,0,0,0);
    *outWidth=int(x.panelWidth);*outHeight=int(x.panelHeight);
    return x.panelSurface;
}
// Intersect the controller's -Z aim ray with the same head-space quad
// submitted to OpenXR. Aim pose is preferred; grip is a compatibility fallback.
KINE_API bool Kine_Filament_XR_GetUIPointer(KineFilamentContext *ctx,int hand,float *u,float *v,float *trigger){
    if(!u || !v || !trigger)return false;
    *u=*v=*trigger=0;
    if(hand<0 || hand>1 || !Kine_Filament_XR_Active(ctx))return false;
    auto &x=*ctx->xr;
    if(!x.panelEnabled || x.panelMirror || !x.frameBegun || !x.rendered ||
       x.state!=XR_SESSION_STATE_FOCUSED || !x.panelWidth || !x.panelHeight)return false;
    auto &c=x.controllers[hand];
    *trigger=c.trigger;
    XrActionStateGetInfo get{XR_TYPE_ACTION_STATE_GET_INFO};get.action=x.aim;get.subactionPath=x.handPaths[hand];
    XrActionStatePose state{XR_TYPE_ACTION_STATE_POSE};
    XrSpace space=x.hands[hand];
    if(x.xrGetActionStatePose(x.session,&get,&state)==XR_SUCCESS && state.isActive)
        space=x.aimSpaces[hand];
    else if(!x.valid[hand+1])return false;
    XrSpaceLocation loc{XR_TYPE_SPACE_LOCATION};
    if(x.xrLocateSpace(space,x.head,x.frame.predictedDisplayTime,&loc)!=XR_SUCCESS ||
       (loc.locationFlags&(XR_SPACE_LOCATION_POSITION_VALID_BIT|XR_SPACE_LOCATION_ORIENTATION_VALID_BIT))!=
       (XR_SPACE_LOCATION_POSITION_VALID_BIT|XR_SPACE_LOCATION_ORIENTATION_VALID_BIT))return false;
    float pose[12];kine_xr_pose(loc.pose,pose);
    const float dx=-pose[5],dy=-pose[8],dz=-pose[11];
    if(dz>=-0.0001f)return false;
    const float t=(-1.4f-pose[2])/dz;
    if(t<=0)return false;
    const float height=0.9f*float(x.panelHeight)/float(x.panelWidth);
    *u=0.5f+(pose[0]+dx*t)/0.9f;
    *v=0.5f-(pose[1]+dy*t+0.35f)/height;
    return std::isfinite(*u) && std::isfinite(*v) && *u>=0 && *u<=1 && *v>=0 && *v<=1;
}
static bool kine_xr_copy(KineFilamentContext *ctx,KineXR &x){
    // The caller has drained the Filament backend before borrowing its queue.
    // Same-queue ordering plus the copy fence replaces two queue-wide waits.
    if(vkResetFences(x.device,1,&x.copyFence)!=VK_SUCCESS ||
       vkResetCommandBuffer(x.command,0)!=VK_SUCCESS)return false;
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};begin.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if(vkBeginCommandBuffer(x.command,&begin)!=VK_SUCCESS)return false;
    for(auto &e:x.eyes){
        auto dst=e.images[e.acquired].image;
        // Same final layout as the existing Filament viewport atlas. Restore it
        // after reading, so Filament's internal layout tracking stays coherent.
        kine_xr_barrier(x.command,e.image,VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_ACCESS_MEMORY_WRITE_BIT|VK_ACCESS_SHADER_READ_BIT,VK_ACCESS_TRANSFER_READ_BIT,VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT);
        kine_xr_barrier(x.command,dst,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,0,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT);
        VkImageCopy copy{};copy.srcSubresource=copy.dstSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1};copy.extent={e.width,e.height,1};
        vkCmdCopyImage(x.command,e.image,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,dst,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,1,&copy);
        kine_xr_barrier(x.command,e.image,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,VK_ACCESS_TRANSFER_READ_BIT,VK_ACCESS_SHADER_READ_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_ALL_COMMANDS_BIT);
        kine_xr_barrier(x.command,dst,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_COLOR_ATTACHMENT_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
    }
    if(x.panelSurface){
        // Skia draws directly into the acquired runtime image. Flush its work
        // and return that image to the layout required by OpenXR before release.
        uint32_t layout=0;
        if(Kine_Skia_Surface_GetVulkanLayout(x.panelSurface,&layout)){
            auto dst=x.panel.images[x.panel.acquired].image;
            if(layout!=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)
                kine_xr_barrier(x.command,dst,VkImageLayout(layout),VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                    VK_ACCESS_MEMORY_WRITE_BIT,VK_ACCESS_COLOR_ATTACHMENT_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                    VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
            x.panelReady=true;
        }else{
            fprintf(stderr,"[KineXR] Could not query native UI layout\n");
            x.panelEnabled=false;
        }
    }
    if(x.panelEnabled && x.panelMirror && ctx->vulkanCompositor){
        void *source=nullptr;uint32_t w=0,h=0,format=0;
        auto &p=x.panel;
        if(Kine_VulkanCompositor_GetXRPanelSource(static_cast<KineVulkanCompositor*>(ctx->vulkanCompositor),&source,&w,&h,&format) && w && h){
            VkFormatProperties srcProps{},dstProps{};
            vkGetPhysicalDeviceFormatProperties(x.physical,VkFormat(format),&srcProps);
            vkGetPhysicalDeviceFormatProperties(x.physical,VK_FORMAT_R8G8B8A8_UNORM,&dstProps);
            if((srcProps.optimalTilingFeatures&VK_FORMAT_FEATURE_BLIT_SRC_BIT) &&
               (dstProps.optimalTilingFeatures&VK_FORMAT_FEATURE_BLIT_DST_BIT)){
                XrSwapchainImageAcquireInfo acquire{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
                XrSwapchainImageWaitInfo wait{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};wait.timeout=XR_INFINITE_DURATION;
                if(kine_xr_ok(x.xrAcquireSwapchainImage(p.swapchain,&acquire,&p.acquired),"acquire UI panel")){
                    p.acquiredImage=true;
                    if(x.xrWaitSwapchainImage(p.swapchain,&wait)==XR_SUCCESS){
                        p.waited=true;
                        if(p.acquired<p.images.size()){
                            const float scale=std::min(float(p.width)/float(w),float(p.height)/float(h));
                            x.panelWidth=std::max(1u,uint32_t(w*scale));x.panelHeight=std::max(1u,uint32_t(h*scale));
                            VkImage src=reinterpret_cast<VkImage>(source), dst=p.images[p.acquired].image;
                            kine_xr_barrier(x.command,src,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT,VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT);
                            kine_xr_barrier(x.command,dst,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,0,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT);
                            VkImageBlit blit{};blit.srcSubresource=blit.dstSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1};
                            blit.srcOffsets[1]={int32_t(w),int32_t(h),1};blit.dstOffsets[1]={int32_t(x.panelWidth),int32_t(x.panelHeight),1};
                            vkCmdBlitImage(x.command,src,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,dst,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,1,&blit,VK_FILTER_NEAREST);
                            kine_xr_barrier(x.command,src,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_ACCESS_TRANSFER_READ_BIT,VK_ACCESS_COLOR_ATTACHMENT_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
                            kine_xr_barrier(x.command,dst,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_COLOR_ATTACHMENT_READ_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT);
                            x.panelReady=true;
                        } else x.failed=true;
                    } else x.failed=true;
                }
            }
        }
    }
    if(vkEndCommandBuffer(x.command)!=VK_SUCCESS)return false;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};submit.commandBufferCount=1;submit.pCommandBuffers=&x.command;
    VkResult result=vkQueueSubmit(x.queue,1,&submit,x.copyFence);
    if(result!=VK_SUCCESS){fprintf(stderr,"[KineXR] copy submit failed (%d)\n",int(result));return false;}
    result=vkWaitForFences(x.device,1,&x.copyFence,VK_TRUE,UINT64_MAX);
    if(result!=VK_SUCCESS)fprintf(stderr,"[KineXR] copy fence failed (%d)\n",int(result));
    return result==VK_SUCCESS;
}
static void kine_xr_end(KineFilamentContext *ctx){
    auto *xp=ctx->xr;if(!xp||!xp->frameBegun)return;
    auto &x=*xp;
    const auto copyStart=std::chrono::steady_clock::now();
    bool ready=x.rendered && !x.failed && kine_xr_copy(ctx,x);
    if(x.rendered)x.copyMs+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-copyStart).count();
    if(x.rendered && !ready){fprintf(stderr,"[KineXR] Stereo copy failed; disabling XR session\n");x.failed=true;}
    XrCompositionLayerProjectionView projection[2]{{XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW},{XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW}};
    for(int i=0;i<2;++i){
        auto &e=x.eyes[i];
        if(e.waited){XrSwapchainImageReleaseInfo release{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};if(!kine_xr_ok(x.xrReleaseSwapchainImage(e.swapchain,&release),"release eye")){ready=false;x.failed=true;}else e.acquiredImage=false;e.waited=false;}
        projection[i].pose=x.views[i].pose;projection[i].fov=x.views[i].fov;
        projection[i].subImage.swapchain=e.swapchain;projection[i].subImage.imageRect.extent={int32_t(e.width),int32_t(e.height)};
    }
    XrCompositionLayerProjection layer{XR_TYPE_COMPOSITION_LAYER_PROJECTION};layer.space=x.local;layer.viewCount=2;layer.views=projection;
    if(x.panelSurface){
        // The copy fence covers the preceding Skia queue work too.
        // On a failed submission, drain the queue before destroying its wrapper.
        if(!ready && x.queue)vkQueueWaitIdle(x.queue);
        Kine_Skia_Surface_Destroy(x.panelSurface);x.panelSurface=nullptr;
    }
    if(x.panel.waited){
        XrSwapchainImageReleaseInfo release{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
        if(!kine_xr_ok(x.xrReleaseSwapchainImage(x.panel.swapchain,&release),"release UI panel")){x.panelReady=false;x.failed=true;}
        else x.panel.acquiredImage=false;
        x.panel.waited=false;
    }
    XrCompositionLayerQuad quad{XR_TYPE_COMPOSITION_LAYER_QUAD};
    quad.space=x.head;quad.eyeVisibility=XR_EYE_VISIBILITY_BOTH;
    if(!x.panelMirror)quad.layerFlags=XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;
    quad.pose.orientation.w=1;quad.pose.position={0,-0.35f,-1.4f};
    quad.size={0.9f,0.9f*float(x.panelHeight)/float(std::max(1u,x.panelWidth))};
    quad.subImage.swapchain=x.panel.swapchain;quad.subImage.imageRect.extent={int32_t(x.panelWidth),int32_t(x.panelHeight)};
    const XrCompositionLayerBaseHeader *layers[]={reinterpret_cast<const XrCompositionLayerBaseHeader*>(&layer),reinterpret_cast<const XrCompositionLayerBaseHeader*>(&quad)};
    ready=ready && !x.failed;
    XrFrameEndInfo end{XR_TYPE_FRAME_END_INFO};end.displayTime=x.frame.predictedDisplayTime;end.environmentBlendMode=x.blend;end.layerCount=ready?(x.panelReady?2:1):0;end.layers=ready?layers:nullptr;
    XrResult ended=x.xrEndFrame(x.session,&end);
    if(ended!=XR_SUCCESS){
        fprintf(stderr,"[KineXR] xrEndFrame returned %d\n",int(ended));x.failed=true;
    }else if(ready){
        const auto now=std::chrono::steady_clock::now();
        if(!x.loggedStereo){
            fprintf(stderr,"[KineXR] First stereo frame submitted\n");x.loggedStereo=true;
            x.measurementStart=now;x.waitMs=0;x.copyMs=0;x.measuredFrames=0;
        }else if(++x.measuredFrames>=120){
            const double elapsed=std::chrono::duration<double>(now-x.measurementStart).count();
            if(elapsed>0)fprintf(stderr,"[KineXR] %.1f submitted FPS; runtime period %.2f ms; avg wait %.2f ms; avg copy %.2f ms\n",
                x.measuredFrames/elapsed,double(x.frame.predictedDisplayPeriod)/1e6,x.waitMs/x.measuredFrames,x.copyMs/x.measuredFrames);
            x.measurementStart=now;x.waitMs=0;x.copyMs=0;x.measuredFrames=0;
        }
        if(x.panelReady && !x.loggedPanel){fprintf(stderr,"[KineXR] First %s UI panel submitted\n",x.panelMirror?"desktop mirror":"native Skia");x.loggedPanel=true;}
    }else{
        x.measurementStart=std::chrono::steady_clock::now();x.waitMs=0;x.copyMs=0;x.measuredFrames=0;
    }
    x.frameBegun=false;
}
static bool kine_xr_defer_end(KineFilamentContext *ctx){
    return ctx && ctx->xr && ctx->xr->panelEnabled && ctx->xr->frameBegun && ctx->xr->rendered;
}
KINE_API void Kine_Filament_XR_FinishFrame(KineFilamentContext *ctx){kine_xr_end(ctx);}
// Keep OpenXR frame pacing and input alive when the editor has no world
// viewport. Never prepare or acquire the desktop swapchain for this path.
KINE_API void Kine_Filament_XR_IdleFrame(KineFilamentContext *ctx) {
    if (!Kine_Filament_XR_Active(ctx)) return;
    if(!ctx->xr->loggedIdle){
        fprintf(stderr,"[KineXR] Idle frame: no active 3D viewport\n");ctx->xr->loggedIdle=true;
    }
    kine_xr_begin(ctx);
    kine_xr_end(ctx);
}
#undef KINE_XR_CORE
#else
static void kine_xr_destroy(KineFilamentContext *) {}
static void kine_xr_begin(KineFilamentContext *) {}
static void kine_xr_render(KineFilamentContext *) {}
static void kine_xr_end(KineFilamentContext *) {}
static bool kine_xr_defer_end(KineFilamentContext *) {return false;}
KINE_API void Kine_Filament_XR_FinishFrame(KineFilamentContext *) {}
KINE_API bool Kine_Filament_XR_GetUIPointer(KineFilamentContext *,int,float *,float *,float *) {return false;}
KINE_API KineSkiaSurface *Kine_Filament_XR_BeginUI(KineFilamentContext *,int,int,int *,int *) {return nullptr;}
KINE_API void Kine_Filament_XR_Poll(KineFilamentContext *ctx) {
    if(!ctx || ctx->xrAttempted)return;
    ctx->xrAttempted=true;
    const char *enable=std::getenv("KINE_VR");
    if(enable && std::strcmp(enable,"1")==0)fprintf(stderr,"[KineXR] OpenXR not compiled for this renderer/platform; install SDK headers and rebuild\n");
}
KINE_API void Kine_Filament_XR_IdleFrame(KineFilamentContext *) {}
KINE_API bool Kine_Filament_XR_Active(KineFilamentContext *) {return false;}
KINE_API bool Kine_Filament_XR_Available(KineFilamentContext *) {return false;}
KINE_API bool Kine_Filament_XR_GetPose(KineFilamentContext *,int,float *) {return false;}
KINE_API bool Kine_Filament_XR_GetControllerState(KineFilamentContext *,int,KineXRControllerState *out) {if(out)*out={};return false;}
KINE_API bool Kine_Filament_XR_SetHaptic(KineFilamentContext *,int,float,float,float) {return false;}
#endif
