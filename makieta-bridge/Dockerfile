FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml ./
COPY makieta_bridge ./makieta_bridge
RUN pip install --no-cache-dir .
USER nobody
ENTRYPOINT ["python", "-m", "makieta_bridge"]
