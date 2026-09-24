# In-game meshes for Roblox: smooth star coin + Sminski torso / arm / leg.
# Each mesh is centred on its bounding box; offsets back to the rig joints are
# written to meshes.json so Models.lua can place them exactly.
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, math, kit, shapes, sminski
from mathutils import Vector

kit.reset()
out = {}

def tri_count(o):
    dg = bpy.context.evaluated_depsgraph_get()
    m = o.evaluated_get(dg).to_mesh()
    n = sum(len(p.vertices) - 2 for p in m.polygons)
    o.evaluated_get(dg).to_mesh_clear()
    return n

def finish(o, name, joint, target_tris):
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects:
        x.select_set(False)
    o.select_set(True)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    n = tri_count(o)
    if n > target_tris:
        d = o.modifiers.new("Dec", "DECIMATE")
        d.ratio = target_tris / n
        bpy.ops.object.modifier_apply(modifier="Dec")
    for p in o.data.polygons:
        p.use_smooth = True
    # recentre on the bounding box
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    centre = (mn + mx) / 2
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.data.transform(__import__("mathutils").Matrix.Translation(-centre))
    o.location = (0, 0, 0)
    o.name = name
    size = mx - mn
    # Blender (x, y, z) with -Y = front  ->  Roblox (x, y, z) with +Z = front:  X = x, Y = z, Z = -y
    out[name] = {
        "size": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
        "offset": [round(centre.x - joint.x, 4), round(centre.z - joint.z, 4), round(-(centre.y - joint.y), 4)],
        "tris": tri_count(o),
    }

# star coin: radius 1, lying in XY; Roblox coins stand up facing the runner, handled in code
body, star = shapes.build_coin("StarCoin", subsurf=2, apply=True)
finish(body, "StarCoin", Vector((0, 0, 0)), 3500)

# torso (joint = torso centre z 1.5)
t = sminski.torso_parts()[0]
kit.smooth(t, 1)
finish(t, "SminskiTorso", Vector((0, 0, 1.5)), 2500)

# arm hanging straight down from the shoulder (joint = shoulder at x=0.62, z=2.08)
arm = sminski._mesh_from(sminski.arm_parts("R", 0.0, 0.0), "Arm", voxel=0.022, smooth_iter=10)
finish(arm, "SminskiArm", Vector((0.62, 0.04, 2.08)), 2500)

# leg (joint = hip at x=0.3, z=0.82)
leg = sminski._mesh_from(sminski.leg_parts("R", 0.0), "Leg", voxel=0.022, smooth_iter=8)
finish(leg, "SminskiLeg", Vector((0.3, 0, 0.82)), 1500)

for o in list(bpy.data.objects):
    if o.name not in out:
        bpy.data.objects.remove(o)
path = os.path.join(kit.OUT_MESH, "SminskiArt.fbx")
bpy.ops.export_scene.fbx(filepath=path, use_selection=False, object_types={"MESH"}, apply_unit_scale=True,
                         apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE")
bpy.ops.wm.obj_export(filepath=os.path.join(kit.OUT_MESH, "SminskiArt.obj"), export_materials=False, forward_axis="NEGATIVE_Z", up_axis="Y")
json.dump(out, open(os.path.join(kit.OUT_MESH, "meshes.json"), "w"), indent=1)
print("MESH_OK", json.dumps(out))
