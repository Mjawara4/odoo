# -*- coding: utf-8 -*-
# Fashion POS — Custom module for a fashion retail shop in Gambia.

{
    'name': 'Fashion POS',
    'version': '1.0.0',
    'category': 'Sales/Point of Sale',
    'summary': 'Custom POS for a fashion shop: auto-SKU, size/color variants, Wave & Afrimoney, inventory control.',
    'description': """
Fashion POS
===========
Customises Odoo POS for a fashion retail shop sourcing inventory from China:

- Auto-generated SKUs per size/color variant (CATEGORY-COLOR-SIZE)
- Fashion product categories: Tops, Bottoms, Dresses, Shoes, Accessories, Underwear
- Clothing size (XS-3XL) and Shoe Size (36-45) attributes with create_variant=always
- Shop Floor + Backroom internal stock locations
- Wave and Afrimoney mobile money payment methods
- Seasonal sale prices / promotions via pos_loyalty
- Daily stock loss logging via stock.scrap
- Staff PIN login with manager-only approval for refunds (pos_hr)
- Profit margin reporting (pos_sale_margin)
- Landed costs on China shipments (stock_landed_costs)
""",
    'depends': [
        'point_of_sale',
        'pos_hr',
        'pos_loyalty',
        'pos_discount',
        'stock_landed_costs',
        'purchase_stock',
        'pos_sale_margin',
    ],
    'data': [
        'security/ir.model.access.csv',
        'data/product_category.xml',
        'data/product_attribute.xml',
        'data/stock_location.xml',
        'data/payment_method.xml',
        'data/pos_category.xml',
        'data/pos_config.xml',
        'views/product_category_view.xml',
        'views/product_template_view.xml',
        'views/stock_scrap_view.xml',
    ],
    'post_init_hook': 'post_init_hook',
    'assets': {
        # Load the branding stylesheet inside the POS frontend app
        'point_of_sale._assets_pos': [
            'fashion_pos/static/src/scss/fashion_pos.scss',
            'fashion_pos/static/src/xml/fashion_receipt.xml',
        ],
    },
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
