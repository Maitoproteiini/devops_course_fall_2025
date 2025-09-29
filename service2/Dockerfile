FROM node:22-alpine
WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

RUN apk update 
RUN apk add curl

COPY src ./src

ENV PORT=8081
EXPOSE 8081

CMD ["npm", "start"]
