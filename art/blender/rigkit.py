# Helpers for building rig-part meshes directly in Roblox joint space.
# Roblox: X right, Y up, +Z = the model's front.  Blender: X right, Z up, -Y front.
#   blender = P @ roblox,  P = [[1,0,0],[0,0,-1],[0,1,0]]
import bpy, bmesh, math, json, os
from mathutils import Vector, Matrix
import kit

P = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
PT = P.transposed()
RECORD = {}


def rb(v):
    return P @ Vector(v)


def angles(rx=0.0, ry=0.0, rz=0.0):
    """Roblox CFrame.Angles(rx, ry, rz) as a 3x3 (Rx * Ry * Rz)."""
    return Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z")


def place(o, center=(0, 0, 0), rot=None):
    """Put a Blender object at a Roblox-space centre/rotation."""
    m = Matrix.Identity(3) if rot is None else rot
    mb = P @ m @ PT
    o.matrix_world = Matrix.Translation(rb(center)) @ mb.to_4x4()
    return o


def ellipsoid(name, size, center=(0, 0, 0), rot=None, seg=48):
    """size = full (X, Y, Z) extents in Roblox axes."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=0.5)
    o = bpy.context.active_object
    o.name = name
    # scale in Roblox axes -> Blender axes
    sb = (size[0], size[2], size[1])
    o.data.transform(Matrix.Diagonal((sb[0], sb[1], sb[2], 1)))
    return place(o, center, rot)


def capsule_y(name, dia, y0, y1, x=0.0, z=0.0, seg=40, rot=None, pivot=None):
    """Vertical (Roblox Y) capsule from y0 to y1 (inclusive of the round ends' centres)."""
    r = dia / 2
    length = abs(y0 - y1)
    prof = []
    rings = 10
    for i in range(rings + 1):
        a = -math.pi / 2 + i / rings * math.pi / 2
        prof.append((max(0.0005, r * math.cos(a)), -length / 2 + r * math.sin(a)))
    for i in range(rings + 1):
        a = i / rings * math.pi / 2
        prof.append((max(0.0005, r * math.cos(a)), length / 2 + r * math.sin(a)))
    o = kit.lathe(name, prof, steps=seg)  # along Blender Z == Roblox Y
    return place(o, (x, (y0 + y1) / 2, z), rot)


def cyl_axis(name, length, dia, center, axis="X", rot=None, seg=48, bevel=0.0):
    """Cylinder along a Roblox axis ('X' / 'Y' / 'Z')."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=dia / 2, depth=length)
    o = bpy.context.active_object  # along Blender Z (= Roblox Y)
    o.name = name
    base = {"Y": Matrix.Identity(3), "X": angles(0, 0, math.pi / 2), "Z": angles(math.pi / 2, 0, 0)}[axis]
    m = base if rot is None else rot @ base
    if bevel:
        b = o.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = 5
        b.limit_method = "ANGLE"
    return place(o, center, m)


def rbox(name, size, center, radius, rot=None):
    """Rounded box (Roblox axes)."""
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    o.name = name
    sb = (size[0], size[2], size[1])
    o.data.transform(Matrix.Diagonal((sb[0], sb[1], sb[2], 1)))
    b = o.modifiers.new("Bevel", "BEVEL")
    b.width = min(radius, min(size) / 2 - 1e-3)
    b.segments = 8
    b.limit_method = "NONE"
    return place(o, center, rot)


def merge(objs, name, voxel, smooth_iter=10):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    if voxel:
        rm = o.modifiers.new("Remesh", "REMESH")
        rm.mode = "VOXEL"
        rm.voxel_size = voxel
        rm.use_smooth_shade = True
        bpy.ops.object.modifier_apply(modifier="Remesh")
        if smooth_iter:
            sm = o.modifiers.new("Smooth", "CORRECTIVE_SMOOTH")
            sm.iterations = smooth_iter
            sm.use_only_smooth = True
            sm.smooth_type = "LENGTH_WEIGHTED"
            bpy.ops.object.modifier_apply(modifier="Smooth")
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def front_uv(o, rect, front_dot=0.25):
    """Front projection UVs (for face textures). rect = (x0, x1, y0, y1) in Roblox
    joint space; faces not facing +Z map to the texture's (transparent) corner."""
    me = o.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    x0, x1, y0, y1 = rect
    for poly in me.polygons:
        nr = PT @ poly.normal  # Roblox-space normal
        facing = nr.z > front_dot
        for li in poly.loop_indices:
            v = PT @ me.vertices[me.loops[li].vertex_index].co
            if facing:
                uv[li].uv = ((v.x - x0) / (x1 - x0), (v.y - y0) / (y1 - y0))
            else:
                uv[li].uv = (0.002, 0.002)


def finish(o, name, target_tris=3000, joint="", uv_rect=None):
    """Decimate, record size + offset from the joint (the joint is the origin)."""
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    n = tris(o)
    if n > target_tris:
        d = o.modifiers.new("Dec", "DECIMATE")
        d.ratio = target_tris / n
        bpy.ops.object.modifier_apply(modifier="Dec")
    for p in o.data.polygons:
        p.use_smooth = True
    if uv_rect:
        front_uv(o, uv_rect)
    vs = [PT @ v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    c = (mn + mx) / 2
    o.data.transform(Matrix.Translation(-(P @ c)))
    o.location = (0, 0, 0)
    o.name = name
    o.data.name = name
    RECORD[name] = {"joint": joint, "size": [round(x, 4) for x in (mx - mn)], "offset": [round(x, 4) for x in c], "tris": tris(o)}
    return o


def export(path_fbx, path_json):
    keep = set(RECORD)
    for ob in list(bpy.data.objects):
        if ob.name not in keep:
            bpy.data.objects.remove(ob)
    bpy.ops.export_scene.fbx(filepath=path_fbx, use_selection=False, object_types={"MESH"}, apply_unit_scale=True,
                             apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE",
                             use_mesh_modifiers=True)
    json.dump(RECORD, open(path_json, "w"), indent=1)
