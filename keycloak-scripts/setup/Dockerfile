# Use an official Node.js runtime as a parent image
FROM node:20-slim

# Set the working directory in the container
WORKDIR /usr/src/app

# Copy package.json and tsconfig.json
COPY package.json tsconfig.json package-lock.json ./

# Install dependencies
# Using npm ci for cleaner installs in CI/build environments
RUN npm ci

# Copy the TypeScript source file
COPY keycloak-webhook-setup.ts .

# No need to explicitly compile with tsc if using ts-node for execution directly
# But if you prefer a compiled version, you could add:
# RUN npm run build # Assuming a build script like "tsc" in package.json

# Command to run the script using ts-node
CMD ["npm", "start"] 