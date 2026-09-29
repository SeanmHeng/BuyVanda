// Tells drizzle-kit where the table definitions live, where to write migration
// files, which database dialect, and how to reach the database.
// https://orm.drizzle.team/docs/drizzle-config-file
import { defineConfig } from "drizzle-kit";
import { config } from "dotenv";


config({ path: "../.env" });

const db_url = process.env.DATABASE_URL
if (!db_url) {throw Error;}

export default defineConfig({
  dialect: 'postgresql',
  schema: './src/db/schema.ts',
  dbCredentials: {
    url: db_url
  }
})