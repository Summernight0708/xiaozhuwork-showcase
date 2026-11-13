const baseUrl = process.env.XIAOZHUWORK_PREVIEW_URL?.replace(/\/$/, "");

if (!baseUrl) {
  throw new Error("XIAOZHUWORK_PREVIEW_URL is required");
}

const projectId = "00000000-0000-4000-8000-000000000001";
const nestedId = "00000000-0000-4000-8000-000000000002";
const routes = [
  "/",
  "/projects",
  "/download",
  "/projects/todos",
  `/projects/${projectId}`,
  `/projects/${projectId}/tasks`,
  `/projects/${projectId}/tasks/${nestedId}`,
  `/projects/${projectId}/files`,
  `/projects/${projectId}/files/${nestedId}`,
  `/projects/${projectId}/reviews`,
  `/projects/${projectId}/reviews/${nestedId}`,
];

let failed = false;
for (const route of routes) {
  const response = await globalThis.fetch(`${baseUrl}${route}`, {
    redirect: "follow",
  });
  const body = await response.text();
  const contentType = response.headers.get("content-type") ?? "";
  const isSpa =
    response.ok &&
    contentType.includes("text/html") &&
    body.includes('id="app"') &&
    body.includes("<title>小猪作业</title>");

  console.log(`${isSpa ? "PASS" : "FAIL"} ${response.status} ${route}`);
  if (!isSpa) failed = true;
}

if (failed) process.exitCode = 1;
