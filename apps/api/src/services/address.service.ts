import { Prisma, prisma } from '@vibethread/database';
import { Errors } from '../lib/errors';
import type { AddressInput, UpdateAddressInput } from '../schemas/shop';

export async function listAddresses(userId: string) {
  return prisma.address.findMany({
    where: { userId },
    orderBy: [{ isDefault: 'desc' }, { id: 'asc' }],
  });
}

export async function createAddress(userId: string, input: AddressInput) {
  const count = await prisma.address.count({ where: { userId } });
  // The first address is always the default.
  const makeDefault = input.isDefault === true || count === 0;

  return prisma.$transaction(async (tx) => {
    if (makeDefault) await tx.address.updateMany({ where: { userId }, data: { isDefault: false } });
    return tx.address.create({ data: { ...input, userId, isDefault: makeDefault } });
  });
}

export async function updateAddress(userId: string, id: string, input: UpdateAddressInput) {
  const found = await prisma.address.findFirst({ where: { id, userId }, select: { id: true } });
  if (!found) throw Errors.notFound('Address not found');

  return prisma.$transaction(async (tx) => {
    if (input.isDefault === true) await tx.address.updateMany({ where: { userId }, data: { isDefault: false } });
    return tx.address.update({ where: { id }, data: input });
  });
}

export async function deleteAddress(userId: string, id: string) {
  const found = await prisma.address.findFirst({ where: { id, userId }, select: { id: true, isDefault: true } });
  if (!found) throw Errors.notFound('Address not found');

  try {
    await prisma.address.delete({ where: { id } });
  } catch (err) {
    // Orders keep a reference to the address they were shipped to.
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2003') {
      throw Errors.conflict('This address is used by an existing order and cannot be deleted');
    }
    throw err;
  }

  if (found.isDefault) {
    const next = await prisma.address.findFirst({ where: { userId }, orderBy: { id: 'asc' }, select: { id: true } });
    if (next) await prisma.address.update({ where: { id: next.id }, data: { isDefault: true } });
  }
}
