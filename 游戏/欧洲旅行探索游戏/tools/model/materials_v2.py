"""Apply photographed CC0 PBR maps while preserving the portable material library."""
from pathlib import Path
import bpy,json

def upgrade(mats,root):
    sources=json.loads((root/'assets/textures/photographic/sources.json').read_text())
    assets={s['asset']:s for s in sources}
    mapping={
      'limestone':'castle_brick_02_white','stone':'castle_brick_01',
      'plaster':'painted_plaster_wall','warm_plaster':'painted_plaster_wall','white':'painted_plaster_wall','ceiling':'painted_plaster_wall','wallpaper':'painted_plaster_wall',
      'wood':'old_wood_floor','dark_wood':'old_wood_floor','parquet':'herringbone_parquet',
      'marble':'marble_01','fabric':'quatrefoil_jacquard_fabric','leather':'fabric_leather_01',
      'paving':'cobblestone_floor_02','rock':'rock_boulder_cracked','rock_dark':'rock_boulder_cracked',
    }
    for name,asset in mapping.items():
        if asset not in assets:continue
        mat=mats[name];nodes=mat.node_tree.nodes;links=mat.node_tree.links;bsdf=nodes.get('Principled BSDF')
        for node in list(nodes):
            if node.type not in ('BSDF_PRINCIPLED','OUTPUT_MATERIAL'):nodes.remove(node)
        for kind,path in assets[asset]['maps'].items():
            img=bpy.data.images.load(str(root/path),check_existing=True)
            if kind!='base':img.colorspace_settings.name='Non-Color'
            node=nodes.new('ShaderNodeTexImage');node.image=img;node.extension='REPEAT'
            if kind=='base':links.new(node.outputs['Color'],bsdf.inputs['Base Color'])
            elif kind=='rough':links.new(node.outputs['Color'],bsdf.inputs['Roughness'])
            elif kind=='normal':
                normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.55 if name in ('plaster','white','ceiling') else .85
                links.new(node.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
        mat['source_asset']=asset;mat['source_license']='CC0'
    glow=mats['emissive'].node_tree.nodes.get('Principled BSDF')
    glow.inputs['Emission Color'].default_value=(1,.78,.43,1);glow.inputs['Emission Strength'].default_value=2.0
    return mats
