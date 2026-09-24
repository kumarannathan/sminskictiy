# Export the Sminski City building kit for Roblox.
#
#   Blender --background --factory-startup --python art/blender/export_buildings.py
#
# Writes:
#   art/meshes/SminskiCity.fbx   -- every kit piece, one object each
#   art/meshes/buildings.json    -- size / offset / tris per piece
#
# In Studio: import the FBX, drop the parts under
#   ReplicatedStorage.SminskiAssets.Props
# named exactly as they are here. game/Props.lua already looks for them by
# name and CityKit's K.prop() will start using each one the moment its
# catalog entry is marked "approved" -- until then the part-built fallback
# keeps running, so importing a half-finished kit cannot break the city.
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, kit, buildings
from mathutils import Vector, Matrix

kit.reset()
out = {}


def tri_count(o):
    dg = bpy.context.evaluated_depsgraph_get()
    m = o.evaluated_get(dg).to_mesh()
    n = sum(len(p.vertices) - 2 for p in m.polygons)
    o.evaluated_get(dg).to_mesh_clear()
    return n


# Triangle budgets by category (.claude/rules/performance.md: silhouette gets
# the geometry, hidden edges do not). Street furniture is instanced hundreds
# of times, so it is held far tighter than a facade module.
BUDGET = {
    "SM_Store_Ground_A": 2600,
    "SM_Store_Floor_A": 1200,
    "SM_Store_Roof_A": 900,
    "SM_Store_Corner_A": 700,
    "bench": 500, "lamp": 600, "planter": 400, "trashcan": 300,
    "hydrant": 300, "mailbox": 300, "bikerack": 300,
    "tree": 900, "pine": 900, "bush": 400, "flowers": 300,
}


def finish(o, name, origin=None):
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    # apply transforms: no arbitrary scale reaches production (blender.md)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    n = tri_count(o)
    budget = BUDGET.get(name)
    if budget is None:
        base = name.rsplit("_", 1)[0]
        budget = BUDGET.get(base, 1200)
    if n > budget:
        d = o.modifiers.new("Dec", "DECIMATE")
        d.ratio = budget / n
        bpy.ops.object.modifier_apply(modifier="Dec")

    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    size = mx - mn
    centre = (mn + mx) / 2
    # Offsets are measured from the WHOLE piece's ground contact point, not
    # from this sub-mesh's own bounding box -- otherwise a tree's canopy would
    # be placed with its own base on the floor instead of up the trunk.
    ground = origin if origin is not None else Vector((centre.x, centre.y, mn.z))
    off = centre - ground

    o.name = name
    # Blender (x, y, z), front = -Y  ->  the city kit's frame, front = -Z:
    #   X = -x, Y = z, Z = y   (a proper rotation; verified in Studio against
    #   the part-built bench -- the rig pipeline's mapping is the mirror of
    #   this because the rig faces +Z, so do NOT copy export_meshes.py here)
    out[name] = {
        "size": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
        "offset": [round(-off.x, 4), round(off.z, 4), round(off.y, 4)],
        "tris": tri_count(o),
    }
    return o


# Placeholder materials, one per role. They exist so the mesh can be SPLIT by
# role on export -- a tree has to arrive in Roblox as a brown trunk mesh and a
# green canopy mesh, because a MeshPart carries exactly one colour.
# The actual colours live in game/Props.lua, not here.
ROLE_MATS = {r: kit.mat("role_" + r, kit.srgb(200, 200, 200))
             for r in ("wall", "accent", "glass", "stone", "timber", "metal",
                       "leaf", "leaf2", "door")}
buildings.use(ROLE_MATS)
MAT_ROLE = {m.name: r for r, m in ROLE_MATS.items()}


def piece_origin(obj):
    """The whole piece's ground contact point, before it is split."""
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    return Vector(((min(v.x for v in bb) + max(v.x for v in bb)) / 2,
                   (min(v.y for v in bb) + max(v.y for v in bb)) / 2,
                   min(v.z for v in bb)))


def split_by_role(obj, base):
    """Separate a built piece into one object per material role."""
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    if len(obj.data.materials) <= 1:
        role = MAT_ROLE.get(obj.data.materials[0].name, "wall") if obj.data.materials else "wall"
        obj.name = "%s_%s" % (base, role)
        return [obj]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    bpy.ops.object.mode_set(mode="OBJECT")
    pieces = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    named = []
    for o in pieces:
        role = "wall"
        if o.data.materials and o.data.materials[0]:
            role = MAT_ROLE.get(o.data.materials[0].name, "wall")
        o.name = "%s_%s" % (base, role)
        named.append(o)
    return named


for base in sorted(buildings.KIT):
    obj = buildings.KIT[base](base)
    origin = piece_origin(obj)
    for piece in split_by_role(obj, base):
        finish(piece, piece.name, origin)
        o = out[piece.name]
        print("  built %-26s %5d tris  offset %s" % (piece.name, o["tris"], o["offset"]))

# lay the pieces out in a row so the FBX is readable when opened by hand
x = 0.0
for name in sorted(out):
    o = bpy.data.objects[name]
    w = out[name]["size"][0]
    o.location = (x + w / 2, 0, 0)
    x += w + 8

os.makedirs(kit.OUT_MESH, exist_ok=True)

# ONE FILE PER PIECE, under art/meshes/citykit/. Roblox imports a single mesh
# far more predictably than a bundle, and each file becomes its own MeshPart
# with the right name, so there is nothing to rename afterwards.
parts_dir = os.path.join(kit.OUT_MESH, "citykit")
os.makedirs(parts_dir, exist_ok=True)
# clear stale pieces: role names change when a builder is re-tagged, and a
# leftover file from an older split will not match anything in Props.lua
for old_f in os.listdir(parts_dir):
    if old_f.endswith(".fbx"):
        os.remove(os.path.join(parts_dir, old_f))
for name in sorted(out):
    for o in bpy.data.objects:
        o.select_set(o.name == name)
    bpy.context.view_layer.objects.active = bpy.data.objects[name]
    bpy.ops.export_scene.fbx(filepath=os.path.join(parts_dir, name + ".fbx"),
                             use_selection=True, object_types={"MESH"},
                             apply_unit_scale=True, bake_space_transform=True,
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE")
for o in bpy.data.objects:
    o.select_set(False)
print("per-piece files -> %s" % parts_dir)

fbx = os.path.join(kit.OUT_MESH, "SminskiCity.fbx")
bpy.ops.export_scene.fbx(filepath=fbx, use_selection=False, object_types={"MESH"},
                         apply_unit_scale=True, bake_space_transform=True,
                         axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE")

# PropMeshes.lua -- the generated size/offset table the game reads, exactly as
# RigMeshes.lua does for the character. Never hand-edit it; re-run this script.
lua = os.path.join(os.path.dirname(kit.ROOT), "game", "PropMeshes.lua")
if not os.path.isdir(os.path.dirname(lua)):
    lua = os.path.join(kit.OUT_MESH, "PropMeshes.lua")
with open(lua, "w") as f:
    f.write("-- PropMeshes (ReplicatedStorage.SminskiShared.PropMeshes)\n")
    f.write("-- GENERATED by art/blender/export_buildings.py -- do not hand-edit.\n")
    f.write("-- size/offset for every sub-mesh of the city kit, in studs. offset is\n")
    f.write("-- measured from the whole piece's ground contact point.\n\n")
    f.write("local V = Vector3.new\n\nreturn {\n")
    for n in sorted(out):
        sz, of = out[n]["size"], out[n]["offset"]
        f.write("\t[\"%s\"] = { size = V(%s, %s, %s), offset = V(%s, %s, %s) },\n"
                % (n, sz[0], sz[1], sz[2], of[0], of[1], of[2]))
    f.write("}\n")
print("lua table -> %s" % lua)

meta = os.path.join(kit.OUT_MESH, "buildings.json")
with open(meta, "w") as f:
    json.dump(out, f, indent=1, sort_keys=True)

print("\n%d pieces -> %s" % (len(out), fbx))
print("            -> %s" % meta)
print("total tris: %d" % sum(v["tris"] for v in out.values()))
print("\nNext: import the FBX in Studio, put the parts under")
print("ReplicatedStorage.SminskiAssets.Props, then flip each reviewed entry")
print('in game/Props.lua from "pending" to "approved".')
