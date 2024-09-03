FROM node:22

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package.json pnpm-lock.yaml ./

RUN npm install -g pnpm

RUN pnpm install --frozen-lockfile

# If you are building your code for production
# RUN pnpm ci --only=production

# Bundle app source
COPY . ./
RUN pnpm run build
RUN npx prisma generate


EXPOSE 8080

CMD ["pnpm", "run", "start"]
