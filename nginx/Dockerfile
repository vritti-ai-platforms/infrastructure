FROM nginx:alpine

# Copy Nginx configurations
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# Create necessary directories
RUN mkdir -p /var/log/nginx /var/cache/nginx /var/run/nginx \
    && chown -R nginx:nginx /var/log/nginx /var/cache/nginx /var/run/nginx

# Expose HTTP and HTTPS ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:80/health || exit 1

# Run Nginx in foreground as nginx user
USER nginx
CMD ["nginx", "-g", "daemon off;"]
