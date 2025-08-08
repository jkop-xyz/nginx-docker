FROM alpine:latest

# Install nginx with stream module and runtime dependencies
RUN apk add --no-cache \
    nginx \
    nginx-mod-stream \
    wget \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create directories with proper permissions
RUN mkdir -p /var/log/nginx \
    && mkdir -p /var/cache/nginx \
    && mkdir -p /etc/nginx/conf.d \
    && mkdir -p /usr/share/nginx/html \
    && mkdir -p /run/nginx \
    && chown -R nginx:nginx /var/cache/nginx \
    && chown -R nginx:nginx /var/log/nginx \
    && chown -R nginx:nginx /usr/share/nginx/html \
    && chown -R nginx:nginx /run/nginx

# Create a simple index page
RUN echo '<h1>Nginx with Stream Module</h1><p>Ready to serve!</p>' > /usr/share/nginx/html/index.html \
    && chown nginx:nginx /usr/share/nginx/html/index.html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Test nginx config
RUN nginx -t

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1

# Use direct logging to stdout/stderr for Docker logs
CMD ["nginx", "-g", "daemon off;"]