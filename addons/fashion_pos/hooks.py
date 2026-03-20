# -*- coding: utf-8 -*-
"""
Fashion POS — post_init_hook
============================
Seeds a ready-to-sell product catalogue with:
  • POS screen categories (Tops, Bottoms, Dresses, Shoes, Accessories, Underwear, SALE)
  • 25 product templates across all 6 fashion categories
  • Size + colour variants with auto-generated EAN-13 barcodes
  • A "Buy 3+ items → 10% off" promotion in pos_loyalty
  • Stock tracking type set to 'lot' per-variant (optional — commented out if not needed)

Re-run anytime via:
    odoo-bin shell -c /etc/odoo/odoo.conf --no-http \
        -d <dbname> <<< "from odoo.addons.fashion_pos.hooks import post_init_hook; post_init_hook(env)"
"""
import logging

_logger = logging.getLogger(__name__)


# ─── EAN-13 helper ────────────────────────────────────────────────────────────

def _ean13(base12: int) -> str:
    """Return a 13-digit EAN-13 string from a 12-digit integer base."""
    s = str(base12).zfill(12)
    total = sum(int(d) * (1 if i % 2 == 0 else 3) for i, d in enumerate(s))
    return s + str((10 - total % 10) % 10)


# ─── Catalogue definition ─────────────────────────────────────────────────────
# Each row:
#   (display_name, categ_xmlid, gender, price_GMD, pos_categ_name,
#    clothing_sizes_or_None, shoe_sizes_or_None, colors)
#
# • clothing_sizes  → uses the "Clothing Size" attribute (XS-3XL)
# • shoe_sizes      → uses the "Shoe Size" attribute (36-45)
# • colors          → uses the "Color" attribute
# • If neither size list is provided the product gets colour-only variants.

_CATALOGUE = [
    # ── TOPS ──────────────────────────────────────────────────────────────────
    ('Basic T-Shirt',
     'fashion_pos.categ_tops', 'unisex', 150.0, 'Tops',
     ['S', 'M', 'L', 'XL'], None,
     ['White', 'Black', 'Gray', 'Red', 'Blue', 'Pink']),

    ('Polo Shirt',
     'fashion_pos.categ_tops', 'men', 200.0, 'Tops',
     ['S', 'M', 'L', 'XL'], None,
     ['White', 'Black', 'Navy']),

    ('Ladies Blouse',
     'fashion_pos.categ_tops', 'women', 250.0, 'Tops',
     ['XS', 'S', 'M', 'L', 'XL'], None,
     ['White', 'Black', 'Red', 'Pink', 'Blue']),

    ('Kids T-Shirt',
     'fashion_pos.categ_tops', 'kids', 100.0, 'Tops',
     ['XS', 'S', 'M'], None,
     ['White', 'Red', 'Blue', 'Yellow']),

    # ── BOTTOMS ───────────────────────────────────────────────────────────────
    ('Classic Jeans',
     'fashion_pos.categ_bottoms', 'unisex', 350.0, 'Bottoms',
     ['S', 'M', 'L', 'XL', '2XL'], None,
     ['Blue', 'Black', 'Gray']),

    ('Cargo Pants',
     'fashion_pos.categ_bottoms', 'men', 300.0, 'Bottoms',
     ['S', 'M', 'L', 'XL'], None,
     ['Beige', 'Black', 'Gray']),

    ('Casual Shorts',
     'fashion_pos.categ_bottoms', 'unisex', 200.0, 'Bottoms',
     ['S', 'M', 'L', 'XL'], None,
     ['Black', 'Navy', 'Gray']),

    ('Ladies Skirt',
     'fashion_pos.categ_bottoms', 'women', 250.0, 'Bottoms',
     ['XS', 'S', 'M', 'L', 'XL'], None,
     ['Black', 'White', 'Red', 'Blue']),

    # ── DRESSES ───────────────────────────────────────────────────────────────
    ('Summer Dress',
     'fashion_pos.categ_dresses', 'women', 400.0, 'Dresses',
     ['XS', 'S', 'M', 'L', 'XL'], None,
     ['White', 'Red', 'Yellow', 'Blue', 'Pink']),

    ('Maxi Dress',
     'fashion_pos.categ_dresses', 'women', 500.0, 'Dresses',
     ['S', 'M', 'L', 'XL'], None,
     ['Black', 'Navy', 'Purple', 'Green']),

    ('Casual Dress',
     'fashion_pos.categ_dresses', 'women', 350.0, 'Dresses',
     ['XS', 'S', 'M', 'L'], None,
     ['White', 'Pink', 'Blue', 'Gray']),

    # ── SHOES ─────────────────────────────────────────────────────────────────
    ('Sneakers',
     'fashion_pos.categ_shoes', 'unisex', 600.0, 'Shoes',
     None, ['37', '38', '39', '40', '41', '42', '43'],
     ['White', 'Black', 'Gray']),

    ('Sandals',
     'fashion_pos.categ_shoes', 'women', 350.0, 'Shoes',
     None, ['36', '37', '38', '39', '40', '41'],
     ['Brown', 'Black', 'Gold']),

    ('Heels',
     'fashion_pos.categ_shoes', 'women', 500.0, 'Shoes',
     None, ['36', '37', '38', '39', '40'],
     ['Black', 'Red', 'Gold']),

    ('Loafers',
     'fashion_pos.categ_shoes', 'men', 450.0, 'Shoes',
     None, ['40', '41', '42', '43', '44'],
     ['Black', 'Brown']),

    # ── ACCESSORIES (colour-only variants) ────────────────────────────────────
    ('Leather Belt',
     'fashion_pos.categ_accessories', 'unisex', 150.0, 'Accessories',
     None, None,
     ['Black', 'Brown']),

    ('Handbag',
     'fashion_pos.categ_accessories', 'women', 600.0, 'Accessories',
     None, None,
     ['Black', 'Brown', 'Red', 'Beige']),

    ('Backpack',
     'fashion_pos.categ_accessories', 'unisex', 500.0, 'Accessories',
     None, None,
     ['Black', 'Navy', 'Gray']),

    ('Scarf',
     'fashion_pos.categ_accessories', 'women', 100.0, 'Accessories',
     None, None,
     ['Multicolor', 'Black', 'White', 'Red']),

    ('Sunglasses',
     'fashion_pos.categ_accessories', 'unisex', 200.0, 'Accessories',
     None, None,
     ['Black', 'Gold', 'Brown']),

    ('Cap / Hat',
     'fashion_pos.categ_accessories', 'unisex', 150.0, 'Accessories',
     None, None,
     ['Black', 'White', 'Navy', 'Red']),

    # ── UNDERWEAR ─────────────────────────────────────────────────────────────
    ("Women's Bra",
     'fashion_pos.categ_underwear', 'women', 150.0, 'Underwear',
     ['S', 'M', 'L', 'XL'], None,
     ['White', 'Black', 'Pink']),

    ("Women's Panties",
     'fashion_pos.categ_underwear', 'women', 80.0, 'Underwear',
     ['S', 'M', 'L', 'XL'], None,
     ['White', 'Black', 'Pink', 'Red']),

    ("Men's Boxers",
     'fashion_pos.categ_underwear', 'men', 100.0, 'Underwear',
     ['S', 'M', 'L', 'XL'], None,
     ['White', 'Black', 'Gray', 'Blue']),

    ("Men's Briefs",
     'fashion_pos.categ_underwear', 'men', 80.0, 'Underwear',
     ['S', 'M', 'L', 'XL'], None,
     ['White', 'Black', 'Gray']),
]


# ─── Hook entry-point ─────────────────────────────────────────────────────────

def post_init_hook(env):
    """Called once when the module is installed.  Safe to call again manually."""
    _logger.info('Fashion POS: seeding initial catalogue…')
    pos_categs = _ensure_pos_categories(env)
    _ensure_products(env, pos_categs)
    _ensure_loyalty_promotion(env)
    _logger.info('Fashion POS: catalogue seed complete.')


# ─── POS screen categories ────────────────────────────────────────────────────

_POS_CATEGS = ['Tops', 'Bottoms', 'Dresses', 'Shoes', 'Accessories', 'Underwear', 'SALE']


def _ensure_pos_categories(env):
    """Create POS screen categories and return {name: record}."""
    result = {}
    for seq, name in enumerate(_POS_CATEGS, start=1):
        rec = env['pos.category'].search([('name', '=', name)], limit=1)
        if not rec:
            rec = env['pos.category'].create({
                'name': name,
                'sequence': seq * 10,
            })
            _logger.info('Fashion POS: created POS category "%s".', name)
        result[name] = rec
    return result


# ─── Product catalogue ────────────────────────────────────────────────────────

def _ensure_products(env, pos_categs):
    """Create every product in _CATALOGUE with variants and EAN-13 barcodes."""
    # Resolve shared attribute records once
    cs_attr = env['product.attribute'].search([('name', '=', 'Clothing Size')], limit=1)
    ss_attr = env['product.attribute'].search([('name', '=', 'Shoe Size')], limit=1)
    col_attr = env['product.attribute'].search([('name', '=', 'Color')], limit=1)

    if not (cs_attr and ss_attr and col_attr):
        _logger.warning(
            'Fashion POS: one or more product attributes are missing — '
            'run module upgrade to reinstall attribute data, then re-seed.'
        )
        return

    cs_vals  = {v.name: v for v in cs_attr.value_ids}
    ss_vals  = {v.name: v for v in ss_attr.value_ids}
    col_vals = {v.name: v for v in col_attr.value_ids}

    # EAN-13 counter — starts well inside the "internal use" 200… range
    barcode_counter = [200100000000]

    def next_barcode():
        code = _ean13(barcode_counter[0])
        barcode_counter[0] += 1
        return code

    for (name, categ_xml, gender, price, pos_categ_name,
         clothing_sizes, shoe_sizes, colors) in _CATALOGUE:

        if env['product.template'].search([('name', '=', name)], limit=1):
            _logger.info('Fashion POS: "%s" already exists — skipping.', name)
            continue

        categ = env.ref(categ_xml, raise_if_not_found=False)
        if not categ:
            _logger.warning('Fashion POS: category ref "%s" not found.', categ_xml)
            continue

        # Build attribute lines ------------------------------------------------
        attr_lines = []

        if clothing_sizes:
            avs = [cs_vals[s] for s in clothing_sizes if s in cs_vals]
            if avs:
                attr_lines.append((0, 0, {
                    'attribute_id': cs_attr.id,
                    'value_ids': [(6, 0, [v.id for v in avs])],
                }))

        if shoe_sizes:
            avs = [ss_vals[s] for s in shoe_sizes if s in ss_vals]
            if avs:
                attr_lines.append((0, 0, {
                    'attribute_id': ss_attr.id,
                    'value_ids': [(6, 0, [v.id for v in avs])],
                }))

        if colors:
            avs = [col_vals[c] for c in colors if c in col_vals]
            if avs:
                attr_lines.append((0, 0, {
                    'attribute_id': col_attr.id,
                    'value_ids': [(6, 0, [v.id for v in avs])],
                }))

        # Create template ------------------------------------------------------
        pos_categ = pos_categs.get(pos_categ_name)
        vals = {
            'name': name,
            'categ_id': categ.id,
            'type': 'consu',          # Goods (storable) in Odoo 19
            'sale_ok': True,
            'purchase_ok': True,
            'available_in_pos': True,
            'list_price': price,
            'fashion_gender': gender,
            'fashion_origin': 'China',
            'attribute_line_ids': attr_lines,
        }
        if pos_categ:
            vals['pos_categ_ids'] = [(4, pos_categ.id)]

        tmpl = env['product.template'].create(vals)
        variant_count = len(tmpl.product_variant_ids)
        _logger.info(
            'Fashion POS: created "%s" — %d variant(s).', name, variant_count
        )

        # Assign unique EAN-13 barcodes to every variant ----------------------
        for variant in tmpl.product_variant_ids:
            if not variant.barcode:
                variant.barcode = next_barcode()


# ─── Loyalty / promotions ─────────────────────────────────────────────────────

def _ensure_loyalty_promotion(env):
    """Create a simple "buy 3+ → 10% off" promotion linked to the POS config."""
    prog_name = 'Fashion Shop Promotions'
    if env['loyalty.program'].search([('name', '=', prog_name)], limit=1):
        _logger.info('Fashion POS: loyalty promotion already exists.')
        return

    try:
        prog = env['loyalty.program'].create({
            'name': prog_name,
            'program_type': 'promotion',
            'trigger': 'auto',
            'applies_on': 'current',
            'rule_ids': [(0, 0, {
                'reward_point_mode': 'order',
                'minimum_qty': 3,
            })],
            'reward_ids': [(0, 0, {
                'reward_type': 'discount',
                'discount': 10.0,
                'discount_mode': 'percent',
                'discount_applicability': 'order',
                'description': '10% off on orders with 3+ items',
            })],
        })
        # Link to the Fashion Shop POS config
        pos_cfg = env.ref('fashion_pos.pos_config_fashion', raise_if_not_found=False)
        if pos_cfg:
            pos_cfg.write({'use_promotion': True})
            pos_cfg.promotion_program_ids = [(4, prog.id)]
        _logger.info('Fashion POS: loyalty promotion created.')
    except Exception:
        _logger.exception('Fashion POS: could not create loyalty promotion.')
