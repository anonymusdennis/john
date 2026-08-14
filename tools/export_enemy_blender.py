import bpy

out_path = "/home/headadmin/Documents/projects/john/assets/models/enemy.glb"
blend_path = "/home/headadmin/Downloads/Untitled.blend"

if bpy.data.is_saved:
    blend_path = bpy.data.filepath

for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    mesh.uv_layers.active_index = 0

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    use_selection=False,
    export_apply=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_image_format="AUTO",
    export_vertex_color="NONE",
)

print("Exported enemy to", out_path)
