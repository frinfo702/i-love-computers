# %%
import matplotlib.pyplot as plt
import numpy as np
import torch
import torchvision
import torchvision.transforms as transforms

# %%
transform = transforms.Compose(
    [
        transforms.ToTensor(),
        transforms.Normalize((0.495, 0.4822, 0.4465), (0.2470, 0.2435, 0.2616)),
    ]
)

trainset = torchvision.datasets.CIFAR10(
    root="./data", train=True, download=True, transform=transform
)

trainloader = torch.utils.data.DataLoader(
    trainset, batch_size=4, shuffle=True, num_workers=2
)

# classes = (
#     "plane",
#     "car",
#     "bird",
#     "cat",
#     "deer",
#     "dog",
#     "frog",
#     "horse",
#     "ship",
#     "truck",
# )


# def imshow(img):
#     img = img / 2 + 0.5  # unnoramalize
#     npimg = img.numpy()
#     plt.imshow(np.transpose(npimg, (1, 2, 0)))


# # get some random training images
# dataiter = iter(trainloader)
# images, labels = dataiter._next_data()

# imshow(torchvision.utils.make_grid(images))
# print(" ".join("%5s" % classes[labels[j]] for j in range(4)))
