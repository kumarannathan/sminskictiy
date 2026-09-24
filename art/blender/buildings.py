# Sminski City building kit: the modular pieces the city is assembled from.
#
# Style target is the key art -- rounded, chunky, matte, pastel, readable at a
# distance, soft bevels on every silhouette edge. See .claude/rules/design.md
# and .claude/rules/blender.md; this module follows both.
#
# Conventions (blender.md):
#   * 1 Blender unit = 1 Roblox stud.
#   * Origin at the bottom-centre of the footprint, on the ground contact
#     point, so Roblox placement is "put it where it stands".
#   * Local -Y is the street face. export_buildings.py maps that to Roblox +Z.
#   * Every piece is a closed quad mesh with a weighted bevel, no ngons on
#     silhouette edges, no interior faces.
#
# Modules stack: Ground -> Floor (xN) -> Roof. A building is a composition,
# never a single mesh (see .claude/rules/assets.md).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh, math, kit
from mathutils import Vector

# the palette, straight off the key art: warm cream walls, sage and mint
# accents, muted terracotta. Saturated colour is an ACCENT, never the wall.
PAL = {
    "cream":     (252, 246, 226),
    "sage":      (168, 196, 150),
    "mint":      (198, 224, 186),
    "moss":      (122, 158, 104),
    "sand":      (232, 214, 176),
    "clay":      (214, 150, 118),
    "slate":     (118, 124, 128),
    "stone":     (198, 198, 192),
    "glass":     (188, 214, 222),
    "timber":    (170, 128, 92),
    "leaf":      (126, 178, 104),
    "leafDark":  (98, 148, 86),
    "bark":      (150, 116, 84),
    "white":     (250, 250, 246),
    "ink":       (58, 62, 50),
}

# MATERIAL ROLES. A module is not one colour -- the whole point of the key
# art look is that the shopfront reads separately from the wall. Builders tag
# each part with a role; the caller supplies the materials for those roles.
# Roles: wall, accent, glass, stone, timber, metal, leaf, door
ROLES = {}


def use(mats):
    """Set the material for each role for subsequent builds."""
    ROLES.clear()
    ROLES.update(mats or {})


def _paint(obj, role):
    m = ROLES.get(role) or ROLES.get("wall")
    if m is not None:
        kit.assign(obj, m)
    return obj


BEVEL = 0.12          # the soft toy edge; consistent across the whole kit
FLOOR_H = 12.0        # one storey, matching CityKit's fh
UNIT_W = 38.0         # one street-wall unit, matching Places.lua ALONG spacing
UNIT_D = 16.0         # facade depth -- these are street walls, not volumes


# ---------------------------------------------------------------------------
# PRIMITIVES
# ---------------------------------------------------------------------------
def _box(name, size, at=(0, 0, 0), bevel=BEVEL, segments=2):
    """A bevelled box. size and at are (x, y, z); at is the box CENTRE."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    if bevel > 0:
        w = min(bevel, min(size) * 0.34)
        bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                        offset=w, segments=segments, profile=0.5, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    o = kit.new_obj(name, me)
    o.location = at
    return o


def _cyl(name, dia, height, at=(0, 0, 0), seg=20, bevel=BEVEL):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=dia / 2, radius2=dia / 2, depth=height)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                        offset=min(bevel, dia * 0.2), segments=2, profile=0.5, affect="EDGES")
    bm.to_mesh(me)
    bm.free()
    o = kit.new_obj(name, me)
    o.location = at
    return o


def _sphere(name, dia, at=(0, 0, 0), squash=(1, 1, 1), seg=24):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2, radius=dia / 2)
    for v in bm.verts:
        v.co.x *= squash[0]
        v.co.y *= squash[1]
        v.co.z *= squash[2]
    bm.to_mesh(me)
    bm.free()
    o = kit.new_obj(name, me)
    o.location = at
    return o


def _join(name, parts):
    """Join parts into one object, origin left at the world origin."""
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def _ground_origin(o):
    """Origin to the bottom-centre of the footprint (blender.md)."""
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
    cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
    z0 = min(v.z for v in bb)
    bpy.context.scene.cursor.location = (cx, cy, z0)
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.selected_objects:
        x.select_set(False)
    o.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)
    return o


# ---------------------------------------------------------------------------
# BUILDING MODULES
# ---------------------------------------------------------------------------
def ground_storefront(name="SM_Store_Ground_A", w=UNIT_W, d=UNIT_D, h=14.0):
    """Ground floor: recessed shopfront glass, a door, a plinth, an awning.

    This is the piece the player actually reads -- almost all street-level
    detail lives here, so it carries the most geometry in the kit.
    """
    parts = []
    parts.append(_paint(_box(name + "_shell", (w, d, h), (0, 0, h / 2)), "wall"))
    # stone plinth, slightly proud of the wall
    parts.append(_paint(_box(name + "_plinth", (w + 0.8, d + 0.8, 1.4), (0, 0, 0.7)), "stone"))
    face = -d / 2
    # two shopfront windows either side of a recessed door
    for sx in (-1, 1):
        parts.append(_paint(_box(name + "_glass%d" % sx, (13.0, 0.5, 9.0), (sx * 11, face - 0.1, 7.0), bevel=0.06), "glass"))
        parts.append(_paint(_box(name + "_sill%d" % sx, (13.6, 1.6, 0.8), (sx * 11, face - 0.6, 2.2)), "stone"))
        # mullions
        for k in (-1, 0, 1):
            parts.append(_paint(_box(name + "_mull%d_%d" % (sx, k), (0.4, 0.7, 9.0), (sx * 11 + k * 4.2, face - 0.35, 7.0), bevel=0.04), "accent"))
    parts.append(_paint(_box(name + "_door", (8.0, 0.6, 11.0), (0, face - 0.1, 5.6)), "door"))
    parts.append(_paint(_box(name + "_step", (10.0, 2.2, 0.5), (0, face - 1.1, 0.25)), "stone"))
    # the awning: a shallow wedge over the whole frontage
    parts.append(_paint(_box(name + "_awning", (w - 2, 4.6, 0.8), (0, face - 2.3, 13.2), bevel=0.1), "accent"))
    parts.append(_paint(_box(name + "_awningLip", (w - 2, 0.7, 1.6), (0, face - 4.5, 12.6), bevel=0.1), "accent"))
    # the signboard above it
    parts.append(_paint(_box(name + "_sign", (w - 4, 0.8, 4.4), (0, face - 0.5, 17.4)), "accent"))
    return _ground_origin(_join(name, parts))


def floor_module(name="SM_Store_Floor_A", w=UNIT_W, d=UNIT_D, h=FLOOR_H, windows=3):
    """A repeatable upper floor: three windows with frames and sills."""
    parts = [_paint(_box(name + "_shell", (w, d, h), (0, 0, h / 2)), "wall")]
    face = -d / 2
    span = w - 10
    for i in range(windows):
        x = -span / 2 + (span / max(1, windows - 1)) * i if windows > 1 else 0
        parts.append(_paint(_box(name + "_frame%d" % i, (8.4, 0.7, 8.0), (x, face - 0.15, h / 2)), "accent"))
        parts.append(_paint(_box(name + "_pane%d" % i, (7.0, 0.5, 6.6), (x, face - 0.5, h / 2), bevel=0.05), "glass"))
        parts.append(_paint(_box(name + "_sill%d" % i, (9.0, 1.3, 0.7), (x, face - 0.7, h / 2 - 4.4)), "stone"))
    return _ground_origin(_join(name, parts))


def roof_cap(name="SM_Store_Roof_A", w=UNIT_W, d=UNIT_D):
    """Parapet and cornice. The cornice matters: it is what casts the shadow
    line that stops a facade reading as a flat painted board."""
    parts = [
        _paint(_box(name + "_cornice", (w + 1.6, d + 1.6, 1.6), (0, 0, 0.8)), "accent"),
        _paint(_box(name + "_parapet", (w, d, 2.6), (0, 0, 2.9)), "accent"),
        # a hollow roof well, so a rooftop reads as a surface you could stand on
        _paint(_box(name + "_deck", (w - 2.4, d - 2.4, 0.5), (0, 0, 1.85)), "stone"),
    ]
    # rooftop plant: an AC unit, because every real roof has one
    parts.append(_paint(_box(name + "_ac", (5.0, 4.0, 3.0), (w * 0.22, 1.5, 3.6)), "metal"))
    parts.append(_paint(_box(name + "_vent", (1.6, 1.6, 1.8), (-w * 0.26, 1.0, 3.0)), "metal"))
    return _ground_origin(_join(name, parts))


def corner_module(name="SM_Store_Corner_A", d=UNIT_D, h=14.0):
    """A square corner piece so two street walls meet without a seam."""
    parts = [
        _box(name + "_shell", (d, d, h), (0, 0, h / 2)),
        _box(name + "_plinth", (d + 0.8, d + 0.8, 1.4), (0, 0, 0.7)),
    ]
    # chamfered corner window, facing the intersection
    parts.append(_box(name + "_glass", (0.5, 10.0, 9.0), (-d / 2 - 0.1, 0, 7.0), bevel=0.06))
    return _ground_origin(_join(name, parts))


# ---------------------------------------------------------------------------
# STREET FURNITURE  (names match game/Props.lua so the catalog resolves)
# ---------------------------------------------------------------------------
def bench(name="bench"):
    parts = []
    for dy in (-0.5, 0.5):
        parts.append(_paint(_box(name + "_slat%s" % dy, (6.0, 0.8, 0.35), (0, dy, 1.9)), "timber"))
    parts.append(_paint(_box(name + "_back", (6.0, 0.3, 1.4), (0, 1.05, 3.0)), "timber"))
    for sx in (-2.6, 2.6):
        parts.append(_paint(_box(name + "_leg%s" % sx, (0.4, 2.0, 2.0), (sx, 0.1, 1.0)), "metal"))
    return _ground_origin(_join(name, parts))


def lamp(name="lamp"):
    parts = [
        _paint(_cyl(name + "_base", 2.0, 1.2, (0, 0, 0.6)), "metal"),
        _paint(_cyl(name + "_post", 0.8, 13.0, (0, 0, 6.5)), "metal"),
        _paint(_cyl(name + "_collar", 1.4, 0.6, (0, 0, 12.6)), "metal"),
        _paint(_sphere(name + "_globe", 2.2, (0, 0, 14.0)), "glass"),
        _paint(_box(name + "_cap", (2.8, 2.8, 0.5), (0, 0, 15.4)), "metal"),
    ]
    return _ground_origin(_join(name, parts))


def planter(name="planter"):
    parts = [
        _paint(_box(name + "_box", (5.0, 5.0, 2.4), (0, 0, 1.2)), "stone"),
        _paint(_box(name + "_lip", (5.4, 5.4, 0.5), (0, 0, 2.5)), "stone"),
        _paint(_sphere(name + "_shrub", 4.0, (0, 0, 3.4), squash=(1, 1, 0.7)), "leaf"),
    ]
    return _ground_origin(_join(name, parts))


def trashcan(name="trashcan"):
    parts = [
        _cyl(name + "_body", 2.4, 3.0, (0, 0, 1.5)),
        _cyl(name + "_lid", 2.7, 0.5, (0, 0, 3.2)),
    ]
    return _ground_origin(_join(name, parts))


def hydrant(name="hydrant"):
    parts = [
        _cyl(name + "_body", 1.4, 2.4, (0, 0, 1.2)),
        _sphere(name + "_cap", 1.5, (0, 0, 2.5)),
        _cyl(name + "_armL", 0.6, 1.6, (0, 0, 1.6)),
    ]
    parts[2].rotation_euler = (0, math.pi / 2, 0)
    return _ground_origin(_join(name, parts))


def mailbox(name="mailbox"):
    parts = [
        _box(name + "_body", (2.0, 1.6, 2.6), (0, 0, 2.3)),
        _sphere(name + "_top", 2.0, (0, 0, 3.6), squash=(1, 0.8, 0.5)),
        _cyl(name + "_leg", 0.7, 2.0, (0, 0, 1.0)),
    ]
    return _ground_origin(_join(name, parts))


def bikerack(name="bikerack"):
    parts = [_box(name + "_rail", (7.0, 0.4, 0.4), (0, 0, 2.6))]
    for sx in (-3.2, 3.2):
        parts.append(_cyl(name + "_post%s" % sx, 0.5, 2.8, (sx, 0, 1.4)))
    return _ground_origin(_join(name, parts))


def tree(name="tree"):
    """Chunky rounded trunk, simplified blobby canopy, exaggerated proportions
    -- the style bible in one asset (design.md, "shape language")."""
    parts = [_paint(_cyl(name + "_trunk", 1.8, 8.0, (0, 0, 4.0), seg=12), "timber")]
    parts.append(_paint(_sphere(name + "_c0", 12.0, (0, 0, 11.5), squash=(1, 1, 0.84)), "leaf"))
    parts.append(_paint(_sphere(name + "_c1", 8.0, (3.6, 1.6, 9.6), squash=(1, 1, 0.88)), "leaf2"))
    parts.append(_paint(_sphere(name + "_c2", 8.0, (-3.2, -2.0, 10.0), squash=(1, 1, 0.88)), "leaf"))
    parts.append(_paint(_sphere(name + "_c3", 7.0, (-1.0, 0.6, 15.4), squash=(1, 1, 0.9)), "leaf2"))
    return _ground_origin(_join(name, parts))


def pine(name="pine"):
    parts = [_paint(_cyl(name + "_trunk", 2.2, 8.0, (0, 0, 4.0), seg=12), "timber")]
    for k in range(4):
        dia = 14.0 - k * 3.2
        parts.append(_paint(_sphere(name + "_t%d" % k, dia, (0, 0, 8.0 + k * 4.2), squash=(1, 1, 0.34)), "leaf" if k % 2 == 0 else "leaf2"))
    parts.append(_paint(_sphere(name + "_tip", 2.4, (0, 0, 25.5), squash=(1, 1, 1.6)), "leaf2"))
    return _ground_origin(_join(name, parts))


def bush(name="bush"):
    parts = [
        _paint(_sphere(name + "_a", 4.4, (0, 0, 1.5), squash=(1, 1, 0.68)), "leaf"),
        _paint(_sphere(name + "_b", 3.2, (1.3, 0.6, 1.9), squash=(1, 1, 0.7)), "leaf2"),
        _paint(_sphere(name + "_c", 3.0, (-1.2, -0.5, 1.8), squash=(1, 1, 0.7)), "leaf"),
    ]
    return _ground_origin(_join(name, parts))


def flowers(name="flowers"):
    parts = [_paint(_box(name + "_soil", (4.0, 2.0, 0.6), (0, 0, 0.3)), "timber")]
    for i in range(4):
        x = -1.5 + i * 1.0
        parts.append(_paint(_sphere(name + "_f%d" % i, 1.1, (x, ((i % 2) - 0.5) * 0.8, 1.0)), "accent"))
    return _ground_origin(_join(name, parts))


# ---------------------------------------------------------------------------
# THE KIT: name -> builder. export_buildings.py walks this.
# ---------------------------------------------------------------------------
KIT = {
    # modular building pieces
    "SM_Store_Ground_A": ground_storefront,
    "SM_Store_Floor_A": floor_module,
    "SM_Store_Roof_A": roof_cap,
    "SM_Store_Corner_A": corner_module,
    # street furniture -- these names match game/Props.lua exactly
    "bench": bench,
    "lamp": lamp,
    "planter": planter,
    "trashcan": trashcan,
    "hydrant": hydrant,
    "mailbox": mailbox,
    "bikerack": bikerack,
    "tree": tree,
    "pine": pine,
    "bush": bush,
    "flowers": flowers,
}
