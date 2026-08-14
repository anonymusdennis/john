import bpy

out_path = "/home/headadmin/Documents/projects/john/assets/models/potato.glb"
albedo_path = "/home/headadmin/Documents/projects/john/assets/models/potato_albedo.png"

# Ensure UVs exist on all meshes.
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    mesh.uv_layers.active_index = 0

# Wire potato albedo into the mesh material.
mat = None
for m in bpy.data.materials:
    if m.users > 0:
        mat = m
        break
if mat is None:
    mat = bpy.data.materials.new("PotatoMaterial")

mat.use_nodes = True
tree = mat.node_tree
tree.nodes.clear()
output = tree.nodes.new("ShaderNodeOutputMaterial")
bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
tex = tree.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(albedo_path, check_existing=True)
tex.interpolation = "Linear"
tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])

for obj in bpy.data.objects:
    if obj.type == "MESH":
        if obj.data.materials:
            obj.data.materials[0] = mat
        else:
            obj.data.materials.append(mat)

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

print("Exported textured potato to", out_path)
