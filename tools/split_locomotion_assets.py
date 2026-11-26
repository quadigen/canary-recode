#!/usr/bin/env python3
"""Split the retargeted example into a rig and independently selectable clips."""
import copy
from pathlib import Path
from retarget_locomotion import GLB


def compact(asset):
    # Retain accessor indices but empty unused views/accessors, then repack the
    # binary. Animation files keep a skinned mesh for the native model importer.
    used = set()
    for mesh in asset.j.get('meshes', []):
        for primitive in mesh['primitives']:
            used.update(primitive.get('attributes', {}).values())
            if 'indices' in primitive: used.add(primitive['indices'])
            for target in primitive.get('targets', []): used.update(target.values())
    used.update(s['inverseBindMatrices'] for s in asset.j.get('skins', []) if 'inverseBindMatrices' in s)
    for animation in asset.j.get('animations', []):
        for sampler in animation['samplers']: used.update((sampler['input'], sampler['output']))
    views = {asset.j['accessors'][i]['bufferView'] for i in used}
    views.update(image['bufferView'] for image in asset.j.get('images', []) if 'bufferView' in image)
    binary = bytearray()
    remap = {}
    packed = []
    for i in sorted(views):
        view = copy.deepcopy(asset.j['bufferViews'][i])
        binary.extend(b'\0' * (-len(binary) % 4))
        offset = view.get('byteOffset', 0)
        chunk = asset.bin[offset:offset + view['byteLength']]
        view['byteOffset'] = len(binary)
        binary.extend(chunk)
        remap[i] = len(packed); packed.append(view)
    accessors = asset.j['accessors']
    for i in range(len(accessors)):
        if i in used: accessors[i]['bufferView'] = remap[accessors[i]['bufferView']]
        else: accessors[i] = {'componentType': 5126, 'count': 1, 'type': 'SCALAR'}
    for image in asset.j.get('images', []):
        if 'bufferView' in image: image['bufferView'] = remap[image['bufferView']]
    asset.j['bufferViews'] = packed; asset.bin = binary


def main():
    source = Path('assets/locomotion/xbot-locomotion.glb')
    original = GLB(source)
    variants = [('xbot-rig', [])] + [(a['name'].replace('Locomotion_', '').lower(), [a]) for a in original.j['animations']]
    for name, animations in variants:
        asset = GLB(source)
        asset.j['animations'] = copy.deepcopy(animations)
        compact(asset)
        output = source.parent / (name + '.glb')
        asset.write(output)
        print(output, output.stat().st_size)


if __name__ == '__main__': main()
