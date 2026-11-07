FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends python3-cryptography && rm -rf /var/lib/apt/lists/* \
    && groupadd -r ppsync && useradd -r -g ppsync -d /var/lib/promptpanel-sync -s /sbin/nologin ppsync \
    && mkdir -p /var/lib/promptpanel-sync/namespaces /var/lib/promptpanel-sync/backups /opt/promptpanel-sync \
    && chown -R ppsync:ppsync /var/lib/promptpanel-sync /opt/promptpanel-sync

WORKDIR /opt/promptpanel-sync
COPY promptpanel_sync_server.py /opt/promptpanel-sync/promptpanel_sync_server.py
RUN chmod 755 /opt/promptpanel-sync/promptpanel_sync_server.py

USER ppsync
ENV PP_SYNC_HOST=0.0.0.0
ENV PP_SYNC_PORT=18787
ENV PP_SYNC_DATA_DIR=/var/lib/promptpanel-sync

EXPOSE 18787
VOLUME ["/var/lib/promptpanel-sync"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python3 -c "import os, urllib.request, sys; port = os.environ.get('PP_SYNC_PORT', '18787'); sys.exit(0 if urllib.request.urlopen(f'http://127.0.0.1:{port}/v1/health', timeout=3).status == 200 else 1)"

CMD ["python3", "/opt/promptpanel-sync/promptpanel_sync_server.py"]
