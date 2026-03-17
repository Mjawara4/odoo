FROM odoo:17.0

# Switch to root to install extra system dependencies
USER root

# wkhtmltopdf for PDF receipt printing
# (Odoo official image already has it but this ensures the right version)
RUN apt-get update && apt-get install -y --no-install-recommends \
        wkhtmltopdf \
    && rm -rf /var/lib/apt/lists/*

# Copy your forked Odoo source into the image
# (addons are also mounted as a volume at runtime for live reloading)
COPY --chown=odoo:odoo addons /mnt/extra-addons

# Switch back to the odoo user
USER odoo

# Expose HTTP and longpolling ports
EXPOSE 8069 8072
