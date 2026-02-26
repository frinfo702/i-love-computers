import torch
import torchvision.models as models
from torchvision.models import VGG

model = models.vgg16(weights="IMAGENET1K_V1")

# The .pth file typically contains a Python dictionary (a state_dict)
# that maps each layer of a neural network model to its param tensor (weights & biases)
torch.save(model.state_dict(), "model_weights.pth")  # best practice: save `state_dict`

# Loading
# load_state_dict()
model: VGG = models.vgg16()
model.load_state_dict(torch.load("model_weights.pth", weights_only=True))
model.eval()

# Saving