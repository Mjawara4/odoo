# -*- coding: utf-8 -*-
from odoo import fields, models


class ProductCategory(models.Model):
    """Extend product.category with a short code used in auto-SKU generation.

    Example: Tops → TOP, Dresses → DRS, Shoes → SHO
    The code is used by product.template to build the default_code
    (SKU) of each size/color variant automatically.
    """
    _inherit = 'product.category'

    fashion_sku_code = fields.Char(
        string='SKU Code',
        size=5,
        help='Short uppercase code included in auto-generated SKUs, e.g. TOP, DRS, SHO.',
    )
