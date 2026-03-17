# -*- coding: utf-8 -*-
from odoo import api, fields, models


# 3-letter colour abbreviations used in auto-generated SKUs
_COLOR_ABBR = {
    'White': 'WHT', 'Black': 'BLK', 'Gray': 'GRY', 'Grey': 'GRY',
    'Brown': 'BRN', 'Beige': 'BGE', 'Red': 'RED', 'Blue': 'BLU',
    'Green': 'GRN', 'Yellow': 'YLW', 'Orange': 'ORG', 'Pink': 'PNK',
    'Purple': 'PRP', 'Cyan': 'CYN', 'Teal': 'TEL', 'Navy': 'NVY',
    'Gold': 'GLD', 'Silver': 'SLV', 'Maroon': 'MRN', 'Olive': 'OLV',
    'Tan': 'TAN', 'Multicolor': 'MLT',
}

# Attribute names that represent clothing/shoe sizes
_SIZE_ATTR_NAMES = {'size', 'clothing size', 'shoe size', 'shoes size'}


class ProductTemplate(models.Model):
    """Fashion-specific fields on product.template."""

    _inherit = 'product.template'

    fashion_season = fields.Char(
        string='Season',
        help='Season or collection this item belongs to, e.g. SS2025, AW2025.',
    )
    fashion_gender = fields.Selection(
        selection=[
            ('women', 'Women'),
            ('men', 'Men'),
            ('unisex', 'Unisex'),
            ('kids', 'Kids'),
        ],
        string='Gender',
        default='unisex',
    )
    fashion_brand = fields.Char(
        string='Brand / Supplier Label',
        help='Brand name or supplier label printed on the item.',
    )
    fashion_origin = fields.Char(
        string='Origin',
        default='China',
        help='Country of manufacture.',
    )


class ProductProduct(models.Model):
    """Auto-generate a structured SKU (default_code) for every fashion variant.

    Format: CATEGORY-COLOR-SIZE
    Examples:
        TOP-RED-S     → Red top, size Small
        DRS-BLU-M     → Blue dress, size Medium
        SHO-BLK-40    → Black shoe, size 40
        ACC-GLD-OS    → Gold accessory, one-size
    """

    _inherit = 'product.product'

    def _fashion_build_sku(self):
        """Return a suggested SKU string for this variant."""
        tmpl = self.product_tmpl_id
        categ = tmpl.categ_id

        # Category code (fallback to first 3 letters of category name)
        cat_code = (categ.fashion_sku_code or categ.name[:3]).upper()

        color_code = 'STD'
        size_code = 'OS'

        for ptal in tmpl.attribute_line_ids:
            attr_name = ptal.attribute_id.name.lower()

            if attr_name == 'color':
                # Find the colour value for this specific variant
                val = self.product_template_attribute_value_ids.filtered(
                    lambda v: v.attribute_id.name.lower() == 'color'
                )
                if val:
                    color_code = _COLOR_ABBR.get(val[0].name, val[0].name[:3].upper())

            elif attr_name in _SIZE_ATTR_NAMES:
                val = self.product_template_attribute_value_ids.filtered(
                    lambda v: v.attribute_id.name.lower() in _SIZE_ATTR_NAMES
                )
                if val:
                    size_code = val[0].name.upper().replace(' ', '')

        return f'{cat_code}-{color_code}-{size_code}'

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        for record in records:
            if not record.default_code:
                record.default_code = record._fashion_build_sku()
        return records
