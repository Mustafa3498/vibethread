import bcrypt from 'bcryptjs';

const COST = 12;

// Compared against when the email doesn't exist, so response time doesn't leak
// whether an account is registered.
const DUMMY_HASH = bcrypt.hashSync('vibethread-dummy-password', COST);

export const hashPassword = (plain: string) => bcrypt.hash(plain, COST);

export const verifyPassword = (plain: string, hash: string | null | undefined) =>
  bcrypt.compare(plain, hash ?? DUMMY_HASH);
