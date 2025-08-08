# Dockerfile: Custom Nginx with ngx_brotli on Alpine
ARG NGINX_VERSION=1.28.0 # Default, overridden by build-arg in CI/CD
ARG BROTLI_VERSION=1.0.9

# Stage 1: Build Nginx with custom modules
FROM alpine:3.18 AS builder

# Install build dependencies
# Common Nginx build dependencies
# git and curl for downloading sources
# cmake for brotli library
# ca-certificates for secure downloads
RUN apk add --no-cache \
    alpine-sdk \
    pcre-dev \
    zlib-dev \
    openssl-dev \
    curl \
    git \
    cmake \
    ca-certificates \
    linux-headers # Often needed for some low-level builds

# Create a directory for source codes
WORKDIR /usr/src

# Download Nginx source
# Using --retry 5 and --fail to make downloads more robust
RUN curl -fSL --retry 5 --retry-connrefused "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -o nginx-${NGINX_VERSION}.tar.gz \
    && tar -zxvf nginx-${NGINX_VERSION}.tar.gz \
    && rm nginx-${NGINX_VERSION}.tar.gz

# Download ngx_brotli module (requires Google's brotli library)
# First, clone the brotli library, build it statically
# Important: static linking on Alpine to avoid runtime dependency issues in final image
RUN git clone --depth=1 https://github.com/google/brotli.git \
    && cd brotli \
    && mkdir out && cd out \
    && cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local .. \
    && cmake --build . --config Release --target brotlienc \
    && cmake --install .

# Then, clone the ngx_brotli Nginx module
RUN git clone --depth=1 https://github.com/google/ngx_brotli.git

# Configure, compile, and install Nginx
WORKDIR /usr/src/nginx-${NGINX_VERSION}
# List of standard modules often included in official Nginx builds
# --with-compat ensures module compatibility if needed later
# --with-cc-opt and --with-ld-opt for security hardening (PIE/RELRO)
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-threads \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-http_slice_module \
    --with-compat \
    --with-file-aio \
    --with-http_v2_module \
    --with-cc-opt='-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
    --with-ld-opt='-Wl,-z,relro -Wl,-z,now -fPIC' \
    --add-module=/usr/src/ngx_brotli \
    && make -j$(nproc) \
    && make install \
    && rm -rf /usr/src/* # Clean up source code

# Stage 2: Create the final lean image
FROM alpine:3.18

# Install runtime dependencies for Nginx and brotli if not statically linked
# Nginx needs libcrypto/libssl from openssl-libs, pcre, zlib. Alpine often has these as base.
# Ensure only essential runtime libs are included for security and size.
RUN apk add --no-cache \
    openssl \
    pcre \
    zlib \
    ca-certificates # Essential for HTTPS requests from Nginx

# Copy Nginx from the builder stage
# /etc/nginx holds config, /usr/sbin/nginx is the binary, /usr/lib/nginx/modules for dynamic modules
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /usr/lib/nginx/modules /usr/lib/nginx/modules
COPY --from=builder /usr/share/nginx/html /usr/share/nginx/html

# Create Nginx user/group for security best practices
# Nginx typically runs as 'nginx' user
RUN addgroup -S nginx && adduser -S -D -H -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
    && chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx

# Healthcheck for robust container management
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO /dev/null http://localhost/ || exit 1

# Expose Nginx ports
EXPOSE 80 443

# Add OCI labels for better image metadata and for version tracking by CI/CD
# These values are often injected by the CI/CD pipeline if not available at Dockerfile build time
# The CI/CD workflow will override these with actual values from its context
LABEL org.opencontainers.image.version=${NGINX_VERSION} \
      org.opencontainers.image.source="https://github.com/${GITHUB_REPOSITORY}" \
      org.opencontainers.image.url="https://github.com/${GITHUB_REPOSITORY}" \
      org.opencontainers.image.licenses="MIT"

# Define default command to run Nginx
# Using `-g 'daemon off;'` to run in foreground for Docker compatibility
CMD ["nginx", "-g", "daemon off;"]