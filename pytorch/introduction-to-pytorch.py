import torch

z = torch.zeros(5, 3)
print(z)
print(z.dtype)

i = torch.ones((5, 3), dtype=torch.int16)
print(i)

torch.manual_seed(1729)
r1 = torch.rand(2, 2)
print("A rondom tensor:")
print(r1)

r2 = torch.rand(2, 2)
print("\nA different random tensor:")
print(r2)

torch.manual_seed(1729)
r3 = torch.rand(2, 2)
print("\nShould match r1:")
print(r3)

ones = torch.ones(2, 3)
print(ones)

twos = torch.ones(2, 3) * 2  # every element is multipled by 2
print(twos)

threes = ones + twos
print(threes)
print(threes.shape)

# r1 = torch.rand(2, 3)
# r2 = torch.rand(3, 2)
# r3 = r1 + r3

r = torch.rand(2, 2) - 0.5 * 2  # values between -1 and 1
print(r)

print("Absolute value\n")
print(torch.abs(r))

print("Inverse sine\n")
print(torch.asin(r))

print("\nDeterminant")
print(torch.det(r))

print("\nSingular value decompositon")
print(torch.svd(r))

print("\nAverage and standard deviation:")
print(torch.std(r))
print("\nMax:")
print(torch.max(r))
