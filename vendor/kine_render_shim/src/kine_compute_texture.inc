

#if KINE_FILAMENT_USE_VULKAN && !defined(__ANDROID__)
namespace {
std::atomic<uint64_t> kine_compute_texture_bytes{0}, kine_compute_texture_dispatches{0};
struct KineComputeTexture {
    KineFilamentVulkanBackend backend{};
    VkImage image=VK_NULL_HANDLE;
    VkDeviceMemory memory=VK_NULL_HANDLE;
    VkImageView view=VK_NULL_HANDLE;
    VkShaderModule module=VK_NULL_HANDLE;
    VkDescriptorSetLayout descriptorLayout=VK_NULL_HANDLE;
    VkPipelineLayout pipelineLayout=VK_NULL_HANDLE;
    VkPipeline pipeline=VK_NULL_HANDLE;
    VkDescriptorPool descriptorPool=VK_NULL_HANDLE;
    VkDescriptorSet descriptors=VK_NULL_HANDLE;
    VkCommandPool pool=VK_NULL_HANDLE;
    VkCommandBuffer command=VK_NULL_HANDLE;
    VkFence fence=VK_NULL_HANDLE;
    Texture* texture=nullptr;
    uint32_t width=0,height=0;
    uint64_t reserved=0;
    std::string sourceKey;
    template<typename T>T proc(const char* name) const { return kine_vp_device_proc<T>(backend,name); }
    VkDevice device()const{return reinterpret_cast<VkDevice>(backend.device);}
    ~KineComputeTexture(){
        auto d=device();if(!d)return;
        if(fence)proc<PFN_vkDestroyFence>("vkDestroyFence")(d,fence,nullptr);
        if(pool)proc<PFN_vkDestroyCommandPool>("vkDestroyCommandPool")(d,pool,nullptr);
        if(pipeline)proc<PFN_vkDestroyPipeline>("vkDestroyPipeline")(d,pipeline,nullptr);
        if(pipelineLayout)proc<PFN_vkDestroyPipelineLayout>("vkDestroyPipelineLayout")(d,pipelineLayout,nullptr);
        if(descriptorPool)proc<PFN_vkDestroyDescriptorPool>("vkDestroyDescriptorPool")(d,descriptorPool,nullptr);
        if(descriptorLayout)proc<PFN_vkDestroyDescriptorSetLayout>("vkDestroyDescriptorSetLayout")(d,descriptorLayout,nullptr);
        if(module)proc<PFN_vkDestroyShaderModule>("vkDestroyShaderModule")(d,module,nullptr);
        if(view)proc<PFN_vkDestroyImageView>("vkDestroyImageView")(d,view,nullptr);
        if(image)proc<PFN_vkDestroyImage>("vkDestroyImage")(d,image,nullptr);
        if(memory)proc<PFN_vkFreeMemory>("vkFreeMemory")(d,memory,nullptr);
        kine_compute_texture_bytes-=reserved;
    }
};
struct KineComputeExternalImage: KineViewportExternalImage {
    std::shared_ptr<KineComputeTexture> owner;
};
bool kine_compute_texture_initialize(KineFilamentContext* ctx,KineComputeTexture& out,
                                    const uint32_t* words,size_t size,uint32_t width,uint32_t height){
    auto d=out.device();out.width=width;out.height=height;
    VkImageCreateInfo image{};image.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    image.imageType=VK_IMAGE_TYPE_2D;image.format=VK_FORMAT_R8G8B8A8_UNORM;
    image.extent={width,height,1};image.mipLevels=image.arrayLayers=1;image.samples=VK_SAMPLE_COUNT_1_BIT;
    image.tiling=VK_IMAGE_TILING_OPTIMAL;
    image.usage=VK_IMAGE_USAGE_STORAGE_BIT|VK_IMAGE_USAGE_SAMPLED_BIT|VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if(out.proc<PFN_vkCreateImage>("vkCreateImage")(d,&image,nullptr,&out.image)!=VK_SUCCESS)return false;
    VkMemoryRequirements req{};out.proc<PFN_vkGetImageMemoryRequirements>("vkGetImageMemoryRequirements")(d,out.image,&req);
    auto getInstance=reinterpret_cast<PFN_vkGetInstanceProcAddr>(out.backend.getInstanceProcAddr);
    auto getMemory=reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(getInstance(reinterpret_cast<VkInstance>(out.backend.instance),"vkGetPhysicalDeviceMemoryProperties"));
    VkPhysicalDeviceMemoryProperties memory{};getMemory(reinterpret_cast<VkPhysicalDevice>(out.backend.physicalDevice),&memory);
    uint32_t type=UINT32_MAX;for(uint32_t i=0;i<memory.memoryTypeCount;++i)if((req.memoryTypeBits&(1u<<i))&&(memory.memoryTypes[i].propertyFlags&VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)){type=i;break;}
    if(type==UINT32_MAX)return false;
    VkMemoryAllocateInfo allocation{};allocation.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;allocation.allocationSize=req.size;allocation.memoryTypeIndex=type;
    if(out.proc<PFN_vkAllocateMemory>("vkAllocateMemory")(d,&allocation,nullptr,&out.memory)!=VK_SUCCESS||out.proc<PFN_vkBindImageMemory>("vkBindImageMemory")(d,out.image,out.memory,0)!=VK_SUCCESS)return false;
    VkImageViewCreateInfo view{};view.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;view.image=out.image;view.viewType=VK_IMAGE_VIEW_TYPE_2D;view.format=image.format;view.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};
    if(out.proc<PFN_vkCreateImageView>("vkCreateImageView")(d,&view,nullptr,&out.view)!=VK_SUCCESS)return false;
    VkShaderModuleCreateInfo module{};module.sType=VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;module.codeSize=size;module.pCode=words;
    if(out.proc<PFN_vkCreateShaderModule>("vkCreateShaderModule")(d,&module,nullptr,&out.module)!=VK_SUCCESS)return false;
    VkDescriptorSetLayoutBinding binding{};binding.binding=0;binding.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;binding.descriptorCount=1;binding.stageFlags=VK_SHADER_STAGE_COMPUTE_BIT;
    VkDescriptorSetLayoutCreateInfo dl{};dl.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;dl.bindingCount=1;dl.pBindings=&binding;
    if(out.proc<PFN_vkCreateDescriptorSetLayout>("vkCreateDescriptorSetLayout")(d,&dl,nullptr,&out.descriptorLayout)!=VK_SUCCESS)return false;
    VkPipelineLayoutCreateInfo pl{};pl.sType=VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;pl.setLayoutCount=1;pl.pSetLayouts=&out.descriptorLayout;
    if(out.proc<PFN_vkCreatePipelineLayout>("vkCreatePipelineLayout")(d,&pl,nullptr,&out.pipelineLayout)!=VK_SUCCESS)return false;
    VkComputePipelineCreateInfo pipeline{};pipeline.sType=VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;pipeline.layout=out.pipelineLayout;
    pipeline.stage.sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;pipeline.stage.stage=VK_SHADER_STAGE_COMPUTE_BIT;pipeline.stage.module=out.module;pipeline.stage.pName="main";
    if(out.proc<PFN_vkCreateComputePipelines>("vkCreateComputePipelines")(d,VK_NULL_HANDLE,1,&pipeline,nullptr,&out.pipeline)!=VK_SUCCESS)return false;
    VkDescriptorPoolSize ps{VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,1};VkDescriptorPoolCreateInfo dp{};dp.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;dp.maxSets=1;dp.poolSizeCount=1;dp.pPoolSizes=&ps;
    if(out.proc<PFN_vkCreateDescriptorPool>("vkCreateDescriptorPool")(d,&dp,nullptr,&out.descriptorPool)!=VK_SUCCESS)return false;
    VkDescriptorSetAllocateInfo da{};da.sType=VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;da.descriptorPool=out.descriptorPool;da.descriptorSetCount=1;da.pSetLayouts=&out.descriptorLayout;
    if(out.proc<PFN_vkAllocateDescriptorSets>("vkAllocateDescriptorSets")(d,&da,&out.descriptors)!=VK_SUCCESS)return false;
    VkDescriptorImageInfo di{};di.imageView=out.view;di.imageLayout=VK_IMAGE_LAYOUT_GENERAL;
    VkWriteDescriptorSet write{};write.sType=VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;write.dstSet=out.descriptors;write.descriptorCount=1;write.descriptorType=VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;write.pImageInfo=&di;
    out.proc<PFN_vkUpdateDescriptorSets>("vkUpdateDescriptorSets")(d,1,&write,0,nullptr);
    VkCommandPoolCreateInfo cp{};cp.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;cp.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;cp.queueFamilyIndex=out.backend.graphicsQueueFamilyIndex;
    if(out.proc<PFN_vkCreateCommandPool>("vkCreateCommandPool")(d,&cp,nullptr,&out.pool)!=VK_SUCCESS)return false;
    VkCommandBufferAllocateInfo ca{};ca.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;ca.commandPool=out.pool;ca.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY;ca.commandBufferCount=1;
    if(out.proc<PFN_vkAllocateCommandBuffers>("vkAllocateCommandBuffers")(d,&ca,&out.command)!=VK_SUCCESS)return false;
    VkFenceCreateInfo fi{};fi.sType=VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    return out.proc<PFN_vkCreateFence>("vkCreateFence")(d,&fi,nullptr,&out.fence)==VK_SUCCESS;
}
bool kine_compute_texture_run(KineFilamentContext* ctx,KineComputeTexture& out){

    ctx->engine->flushAndWait();auto queue=reinterpret_cast<VkQueue>(out.backend.queue);auto d=out.device();
    if(out.proc<PFN_vkQueueWaitIdle>("vkQueueWaitIdle")(queue)!=VK_SUCCESS)return false;
    if(out.proc<PFN_vkResetCommandPool>("vkResetCommandPool")(d,out.pool,0)!=VK_SUCCESS)return false;
    VkCommandBufferBeginInfo begin{};begin.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;begin.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if(out.proc<PFN_vkBeginCommandBuffer>("vkBeginCommandBuffer")(out.command,&begin)!=VK_SUCCESS)return false;
    VkImageMemoryBarrier barrier{};barrier.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.srcAccessMask=VK_ACCESS_SHADER_READ_BIT;barrier.dstAccessMask=VK_ACCESS_SHADER_WRITE_BIT;
    barrier.oldLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;barrier.newLayout=VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcQueueFamilyIndex=barrier.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED;barrier.image=out.image;barrier.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};
    auto transition=out.proc<PFN_vkCmdPipelineBarrier>("vkCmdPipelineBarrier");
    transition(out.command,VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,0,0,nullptr,0,nullptr,1,&barrier);
    out.proc<PFN_vkCmdBindPipeline>("vkCmdBindPipeline")(out.command,VK_PIPELINE_BIND_POINT_COMPUTE,out.pipeline);
    out.proc<PFN_vkCmdBindDescriptorSets>("vkCmdBindDescriptorSets")(out.command,VK_PIPELINE_BIND_POINT_COMPUTE,out.pipelineLayout,0,1,&out.descriptors,0,nullptr);
    out.proc<PFN_vkCmdDispatch>("vkCmdDispatch")(out.command,(out.width+7)/8,(out.height+7)/8,1);
    barrier.srcAccessMask=VK_ACCESS_SHADER_WRITE_BIT;barrier.dstAccessMask=VK_ACCESS_SHADER_READ_BIT;barrier.oldLayout=VK_IMAGE_LAYOUT_GENERAL;barrier.newLayout=VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    transition(out.command,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,0,0,nullptr,0,nullptr,1,&barrier);
    if(out.proc<PFN_vkEndCommandBuffer>("vkEndCommandBuffer")(out.command)!=VK_SUCCESS)return false;
    if(out.proc<PFN_vkResetFences>("vkResetFences")(d,1,&out.fence)!=VK_SUCCESS)return false;
    VkSubmitInfo submit{};submit.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO;submit.commandBufferCount=1;submit.pCommandBuffers=&out.command;
    if(out.proc<PFN_vkQueueSubmit>("vkQueueSubmit")(queue,1,&submit,out.fence)!=VK_SUCCESS)return false;
    if(out.proc<PFN_vkWaitForFences>("vkWaitForFences")(d,1,&out.fence,VK_TRUE,UINT64_MAX)!=VK_SUCCESS)return false;
    ++kine_compute_texture_dispatches;return true;
}
}
#endif

KINE_API bool Kine_Filament_Shader_DispatchTexture(KineFilamentShader* shader,const char* name,
    const uint32_t* words,size_t size,uint32_t width,uint32_t height){
#if KINE_FILAMENT_USE_VULKAN && !defined(__ANDROID__)
    if(!shader||!shader->ctx||!shader->ctx->engine||!shader->material||!name||!*name||!words||size<20||size>4*1024*1024||size%4||words[0]!=0x07230203||!width||!height||width>1024||height>1024)return false;
    auto* ctx=shader->ctx;if(!ctx->useFilamentOwnedCompositor)return false;
    std::vector<Material::ParameterInfo> parameters(shader->material->getParameterCount());shader->material->getParameters(parameters.data(),parameters.size());
    if(std::none_of(parameters.begin(),parameters.end(),[&](const auto& p){return p.isSampler&&p.samplerType==Material::SamplerType::SAMPLER_2D&&std::strcmp(p.name,name)==0;}))return false;
    auto key=kine_shader_cache::hex(kine_shader_cache::digest({reinterpret_cast<const char*>(words),size}));
    auto found=shader->computeTextures.find(name);
    if(found!=shader->computeTextures.end()&&found->second->width==width&&found->second->height==height&&found->second->sourceKey==key)
        return kine_compute_texture_run(ctx,*found->second);
    if(shader->computeTextures.size()>=16&&found==shader->computeTextures.end())return false;
    const uint64_t bytes=uint64_t(width)*height*4;
    if(kine_compute_texture_bytes.fetch_add(bytes)+bytes>128*1024*1024){kine_compute_texture_bytes-=bytes;return false;}
    auto output=std::make_shared<KineComputeTexture>();output->reserved=bytes;output->sourceKey=key;
    if(!Kine_Filament_GetVulkanBackend(ctx,&output->backend)){kine_compute_texture_bytes-=bytes;output->reserved=0;return false;}
    if(!kine_compute_texture_initialize(ctx,*output,words,size,width,height))return false;
    auto* external=new KineComputeExternalImage();external->owner=output;external->image=output->image;external->width=width;external->height=height;
    backend::Platform::ExternalImageHandle handle(external);
    auto* texture=Texture::Builder().width(width).height(height).levels(1).format(Texture::InternalFormat::RGBA8).usage(Texture::Usage::SAMPLEABLE|Texture::Usage::COLOR_ATTACHMENT).external().build(*ctx->engine);
    if(!texture)return false;
    output->texture=texture;texture->setExternalImage(*ctx->engine,handle);

    if(!kine_compute_texture_run(ctx,*output)){ctx->engine->destroy(texture);return false;}
    Texture* old=nullptr;if(auto previous=shader->textures.find(name);previous!=shader->textures.end())old=previous->second;
    shader->textures[name]=texture;shader->computeTextures[name]=output;kine_refresh_shader_instances(shader);
    if(old)ctx->engine->destroy(old);
    return true;
#else
    (void)shader;(void)name;(void)words;(void)size;(void)width;(void)height;return false;
#endif
}
KINE_API void Kine_Filament_ComputeTextureStats(uint64_t* out){
    if(!out)return;
#if KINE_FILAMENT_USE_VULKAN && !defined(__ANDROID__)
    out[0]=kine_compute_texture_dispatches;out[1]=kine_compute_texture_bytes;
#else
    out[0]=out[1]=0;
#endif
    out[2]=0;
    out[3]=0;
}
