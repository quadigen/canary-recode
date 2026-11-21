import pathlib
import struct
import sys
import unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/"tools"))
import porter

class ContentTests(unittest.TestCase):
    def test_mixed_content(self):
        tags = (0,1,2,1)
        ints = [(v*2).to_bytes(4,"big") for v in tags]
        header = bytes(x for column in zip(*ints) for x in column)
        paths = [b"rbxassetid://123",b"file://face.png"]
        chunk = header + struct.pack("<I",len(paths))
        chunk += b"".join(struct.pack("<I",len(p))+p for p in paths)
        chunk += struct.pack("<I",1) + b"\0\0\0\x02" + struct.pack("<I",0)
        reader = porter.Buf(chunk)
        self.assertEqual(porter.decode_prop(0x22,reader,len(tags),None),
                         [None,("s",paths[0]),None,("s",paths[1])])
        self.assertEqual(reader.p,len(chunk))
    def test_sky_aliases(self):
        self.assertEqual(len(porter.CONTENT_URI_ALIASES["Sky"]),8)
        for property in porter.CONTENT_URI_ALIASES["Sky"].values():
            self.assertEqual(porter.ASSET_PROPERTY_KINDS[property],porter.ASSET_TEXTURE)

if __name__ == "__main__":
    unittest.main()
