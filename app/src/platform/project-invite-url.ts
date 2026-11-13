export interface ProjectInviteUrlContext {
  isNative: boolean;
  webOrigin: string;
  backendUrl: string;
}

export function buildProjectInviteUrl(
  token: string,
  context: ProjectInviteUrlContext,
): string {
  let origin = context.webOrigin;
  if (context.isNative) {
    const backend = new URL(context.backendUrl);
    if (backend.protocol !== "https:" || backend.hostname === "localhost") {
      throw new Error(
        "A native invitation link needs a public HTTPS backend URL",
      );
    }
    origin = backend.origin;
  }
  return `${origin}/invite/${encodeURIComponent(token)}`;
}
