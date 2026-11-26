# Kinemium Luau definitions generator

## Regeneration

Run from the engine repo root:

```sh
python3 tools/vscode-kinemium/generate_definitions.py \
  --output ../kinemium-luau-lsp/editors/code/definitions/kinemiumTypes.d.luau
python3 -m unittest discover -s tools/vscode-kinemium -p 'test_*.py'
```

Engine registrations drive the generated list of 2D/3D classes, services, datatypes, enums, exposed members and constructors. Conservative native signature inference falls back to `any` where detailed types cannot be established safely. `Instance.new` only includes a few specialized overloads: larger intersection types can exceed Luau's checker complexity limit. A disjoint literal-name union provides a constructor fallback for the other registered creatable classes; an arbitrary dynamic string may need narrowing.

## Generated definitions

Generate API definitions from engine registrations using:

```sh
python3 tools/vscode-kinemium/generate_definitions.py --help
```

Use the generated definitions with the Kinemium Luau language server. The generator covers registered classes, services, datatypes, enums and API members, while leaving dynamic native signatures conservative where exact types cannot be verified.

For GPUCompute method signatures, return values and supported descriptor tables, see [GPUCompute.md](GPUCompute.md).
