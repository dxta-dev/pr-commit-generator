FROM node:24-slim

RUN apt-get update \
  && apt-get install -y git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

CMD ["npm", "run", "automation"]
