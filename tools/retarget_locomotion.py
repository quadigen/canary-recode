#!/usr/bin/env python3
"""Retarget authored Quaternius UAL glTF clips to a Mixamo GLB (requires numpy)."""
import argparse, json, math, re, struct
from pathlib import Path
import numpy as np


def quat_matrix(q):
    q=np.array(q,dtype=float); q/=np.linalg.norm(q)
    x,y,z,w=q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])


def matrix_quat(r):
    t=np.trace(r)
    if t>0:
        s=math.sqrt(t+1)*2; q=np.array([(r[2,1]-r[1,2])/s,(r[0,2]-r[2,0])/s,(r[1,0]-r[0,1])/s,.25*s])
    else:
        i=int(np.argmax(np.diag(r))); j=(i+1)%3; k=(i+2)%3
        s=math.sqrt(max(1+r[i,i]-r[j,j]-r[k,k],1e-12))*2
        q=np.zeros(4); q[i]=.25*s; q[j]=(r[j,i]+r[i,j])/s; q[k]=(r[k,i]+r[i,k])/s; q[3]=(r[k,j]-r[j,k])/s
    return q/np.linalg.norm(q)


def rotation(m):
    r=m[:3,:3].copy(); r/=np.linalg.norm(r,axis=0)
    return r


class GLB:
    def __init__(self,path):
        data=Path(path).read_bytes(); assert data[:4]==b'glTF'
        size=struct.unpack_from('<I',data,12)[0]
        self.j=json.loads(data[20:20+size]); at=20+size
        self.bin=bytearray(data[at+8:at+8+struct.unpack_from('<I',data,at)[0]])
        self.nodes=self.j['nodes']; self.parents={c:i for i,n in enumerate(self.nodes) for c in n.get('children',[])}
        self.names={n.get('name',''):i for i,n in enumerate(self.nodes)}
    def accessor(self,index):
        a=self.j['accessors'][index]; v=self.j['bufferViews'][a['bufferView']]
        assert 'sparse' not in a
        dt={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
        width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        item=np.dtype(dt).itemsize
        return np.ndarray((a['count'],width),dtype=dt,buffer=self.bin,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',item*width),item)).copy()
    def local(self,i,changes):
        n=self.nodes[i]
        if 'matrix' in n:
            assert i not in changes
            return np.array(n['matrix']).reshape((4,4),order='F')
        c=changes.get(i,{})
        m=np.eye(4); m[:3,:3]=quat_matrix(c.get('rotation',n.get('rotation',[0,0,0,1])))@np.diag(c.get('scale',n.get('scale',[1,1,1])))
        m[:3,3]=c.get('translation',n.get('translation',[0,0,0])); return m
    def globals(self,changes=None):
        changes=changes or {}; out={}
        def visit(i):
            if i not in out: out[i]=(visit(self.parents[i]) if i in self.parents else np.eye(4))@self.local(i,changes)
            return out[i]
        for i in range(len(self.nodes)):visit(i)
        return out
    def animation(self,name):
        a=next(x for x in self.j['animations'] if x['name']==name)
        channels=[]
        for c in a['channels']:
            sm=a['samplers'][c['sampler']]
            assert sm.get('interpolation','LINEAR') in ['LINEAR','STEP']
            channels.append((c['target']['node'],c['target']['path'],self.accessor(sm['input'])[:,0],self.accessor(sm['output']),sm.get('interpolation','LINEAR')))
        return channels
    @staticmethod
    def sample(channels,t):
        out={}
        for node,path,times,values,interp in channels:
            k=int(np.clip(np.searchsorted(times,t,side='right')-1,0,len(times)-1)); value=values[k].copy()
            if k+1<len(times) and interp!='STEP':
                u=float(np.clip((t-times[k])/(times[k+1]-times[k]),0,1)); nxt=values[k+1]
                if path=='rotation':
                    d=float(np.dot(value,nxt)); nxt=nxt if d>=0 else -nxt; d=abs(d)
                    if d<.9995:
                        angle=math.acos(min(d,1)); value=(math.sin((1-u)*angle)*value+math.sin(u*angle)*nxt)/math.sin(angle)
                    else:value=value*(1-u)+nxt*u
                    value/=np.linalg.norm(value)
                else:value=value*(1-u)+nxt*u
            out.setdefault(node,{})[path]=value
        return out
    def append(self,values,kind):
        a=np.asarray(values,dtype='<f4'); self.bin.extend(b'\0'*(-len(self.bin)%4)); offset=len(self.bin); self.bin.extend(a.tobytes())
        vi=len(self.j['bufferViews']); self.j['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':a.nbytes})
        acc={'bufferView':vi,'componentType':5126,'count':len(a),'type':kind}
        if kind=='SCALAR':acc.update(min=[float(a.min())],max=[float(a.max())])
        index=len(self.j['accessors']); self.j['accessors'].append(acc); return index
    def write(self,path):
        self.j['buffers'][0]['byteLength']=len(self.bin)
        data=json.dumps(self.j,separators=(',',':')).encode(); data+=b' '*(-len(data)%4)
        b=bytes(self.bin); b+=b'\0'*(-len(b)%4)
        Path(path).write_bytes(struct.pack('<4sII',b'glTF',2,28+len(data)+len(b))+struct.pack('<I4s',len(data),b'JSON')+data+struct.pack('<I4s',len(b),b'BIN\0')+b)


def mapping(target,source):
    names={re.sub(r'_\d+$','',n.split(':')[-1]):i for n,i in target.names.items()}
    pairs={'Hips':'pelvis','Spine':'spine_01','Spine1':'spine_02','Spine2':'spine_03','Neck':'neck_01','Head':'Head'}
    for side,suffix in [('Left','l'),('Right','r')]:
        for t,s in [('Shoulder','clavicle'),('Arm','upperarm'),('ForeArm','lowerarm'),('Hand','hand'),('UpLeg','thigh'),('Leg','calf'),('Foot','foot'),('ToeBase','ball')]: pairs[side+t]=s+'_'+suffix
        for finger in ['Thumb','Index','Middle','Ring','Pinky']:
            for k in range(1,4):pairs[f'{side}Hand{finger}{k}']=f'{finger.lower()}_0{k}_{suffix}'
    return {names[t]:source.names[s] for t,s in pairs.items() if t in names and s in source.names}


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('source'); ap.add_argument('target'); ap.add_argument('output'); args=ap.parse_args()
    src=GLB(args.source); target=GLB(args.target)
    # Normalize cancelling FBX/Sketchfab wrapper rotations. Globals and skin
    # binds stay identical, while importers that discard the scene-root
    # transform no longer apply a different frame to animated root channels.
    skin_joints={i for skin in target.j.get('skins',[]) for i in skin['joints']}
    for root in target.j['scenes'][target.j.get('scene',0)].get('nodes',[]):
        children=target.nodes[root].get('children',[])
        if len(children)==1 and root not in skin_joints and children[0] not in skin_joints:
            child=children[0]
            if np.allclose(target.local(root,{})@target.local(child,{}),np.eye(4),atol=1e-5):
                for node in [root,child]:
                    for field in ['matrix','translation','rotation','scale']:target.nodes[node].pop(field,None)
    ref=src.globals(src.sample(src.animation('A_TPose'),0)); bind=target.globals(); mp=mapping(target,src)
    hip=target.names[next(n for n in target.names if re.sub(r'_\d+$','',n.split(':')[-1])=='Hips')]; sh=mp[hip]
    ratio=bind[hip][1,3]/ref[sh][1,3]
    # The packs and Mixamo are both Y-up; align their feet's forward axes.
    sf=ref[src.names['ball_l']][:3,3]-ref[src.names['foot_l']][:3,3]
    tf=bind[next(i for n,i in target.names.items() if 'LeftToeBase' in n)][:3,3]-bind[next(i for n,i in target.names.items() if 'LeftFoot' in n)][:3,3]
    yaw=math.atan2(tf[0],tf[2])-math.atan2(sf[0],sf[2]); basis=quat_matrix([0,math.sin(yaw/2),0,math.cos(yaw/2)])
    selected={'Idle':'Idle_Loop','Walk':'Walk_Loop','Run':'Jog_Fwd_Loop','Sprint':'Sprint_Loop','Jump':'Jump_Start','Fall':'Jump_Loop','Land':'Jump_Land'}
    target.j['animations']=[]; manifest={}
    joints=set(target.j['skins'][0]['joints'])
    for name,source_name in selected.items():
        channels=src.animation(source_name); duration=max(float(x[2][-1]) for x in channels)
        times=np.linspace(0,duration,max(2,round(duration*30)+1)); rotations={i:[] for i in mp}; translations=[]
        target_feet=[i for n,i in target.names.items() if re.sub(r'_\d+$','',n.split(':')[-1]) in ['LeftFoot','RightFoot']]
        source_feet=[src.names['foot_l'],src.names['foot_r']]
        for t in times:
            sg=src.globals(src.sample(channels,float(t))); out={}; local_rot={}
            def solve(i):
                if i in out:return out[i]
                parent=solve(target.parents[i]) if i in target.parents else np.eye(4)
                local=target.local(i,{})
                if i in mp:
                    si=mp[i]; desired=basis@rotation(sg[si])@rotation(ref[si]).T@basis.T@rotation(bind[i])
                    lr=rotation(parent).T@desired; q=matrix_quat(lr)
                    if rotations[i] and np.dot(q,rotations[i][-1])<0:q=-q
                    rotations[i].append(q); local[:3,:3]=lr@np.diag(np.linalg.norm(local[:3,:3],axis=0))
                    if i==hip:
                        p=bind[i][:3,3]+basis@(sg[si][:3,3]-ref[si][:3,3])*ratio
                        local[:3,3]=(np.linalg.inv(parent)@np.r_[p,1])[:3]; translations.append(local[:3,3].copy())
                out[i]=parent@local; return out[i]
            for i in range(len(target.nodes)):solve(i)
            # Bake the source's authored foot height onto the differently
            # proportioned target. This is asset retargeting, not runtime IK.
            expected=min(bind[i][1,3] for i in target_feet)+(min(sg[i][1,3] for i in source_feet)-min(ref[i][1,3] for i in source_feet))*ratio
            correction=expected-min(out[i][1,3] for i in target_feet)
            parent=out[target.parents[hip]] if hip in target.parents else np.eye(4)
            translations[-1]+=np.linalg.inv(parent[:3,:3])@np.array([0,correction,0])
        ta=target.append(times,'SCALAR'); animation={'name':'Locomotion_'+name,'samplers':[],'channels':[]}
        for i,values in rotations.items():
            if i not in joints:continue
            oi=target.append(values,'VEC4'); si=len(animation['samplers']); animation['samplers'].append({'input':ta,'output':oi,'interpolation':'LINEAR'}); animation['channels'].append({'sampler':si,'target':{'node':i,'path':'rotation'}})
        oi=target.append(translations,'VEC3'); si=len(animation['samplers']); animation['samplers'].append({'input':ta,'output':oi,'interpolation':'LINEAR'}); animation['channels'].append({'sampler':si,'target':{'node':hip,'path':'translation'}})
        target.j['animations'].append(animation); manifest[name]={'source':source_name,'duration':duration,'joints':len(rotations)}
    target.j.setdefault('asset',{})['extras']={'locomotionSource':'Quaternius Universal Animation Library Standard, CC0 1.0','retargetedTo':'original XBot Mixamo skeleton','rootMotion':False}
    target.write(args.output); Path(args.output).with_suffix('.json').write_text(json.dumps({'clips':manifest,'sourceToTargetScale':ratio},indent=2)+'\n')
    print(json.dumps(manifest,indent=2));print('Retargeted',len(mp),'joints; scale',ratio)

if __name__=='__main__':main()
