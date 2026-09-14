/** A stable identifier for a canonical DigitalMe principal. */
export type PrincipalId = string;

/** Warden's canonical representation of a person or system. */
export interface DigitalMePrincipal {
  id: PrincipalId;
  displayName?: string;
  kind: 'person' | 'service';
}

/** An identity asserted by an external authentication provider. */
export interface ProviderIdentity<TProvider extends string = string> {
  provider: TProvider;
  subject: string;
  authenticatedAt: string;
}

/** Converts provider-specific credentials into a provider identity. */
export interface IdentityProvider<
  TCredential,
  TIdentity extends ProviderIdentity,
> {
  readonly id: TIdentity['provider'];
  authenticate(credential: TCredential): Promise<TIdentity>;
}

/** The identity facts returned by GitHub authentication. */
export interface GitHubIdentity extends ProviderIdentity<'github'> {
  login: string;
  userId: number;
}

/** A provider-to-principal association, independent of authentication. */
export interface IdentityBinding<
  TIdentity extends ProviderIdentity = ProviderIdentity,
> {
  id: string;
  principalId: PrincipalId;
  providerIdentity: TIdentity;
  boundAt: string;
}

/** The binding between a GitHub account and a DigitalMe principal. */
export type GitHubProviderBinding = IdentityBinding<GitHubIdentity>;

/** Resolves an authenticated provider identity to its DigitalMe principal. */
export interface PrincipalResolver {
  resolve(identity: ProviderIdentity): Promise<DigitalMePrincipal | null>;
}

/** Identity context attached to a Warden session. */
export interface WardenSessionIdentity {
  principal: DigitalMePrincipal;
  bindings: readonly IdentityBinding[];
  sessionId: string;
}
