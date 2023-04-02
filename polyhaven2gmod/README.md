# polyhaven2gmod

Using the PolyHaven API and VTFCmd, `polyhaven2gmod` allows you to generate a ready-to-go GMod material from a PolyHaven material with VisTrace MRAO mapping support.

# Usage

It's recommended to run `polyhaven2gmod` in its directory and then copy the materials over to GMod and VisTrace if necessary. The VMT also contains a transform so you can adjust how the texture looks.

The usage is described in the command, but the general workflow is:

1. Find a material you want to use on [PolyHaven](https://polyhaven.com/textures)
   <br></br>
   ![step_1](https://i.imgur.com/a8GsOyX.png)
2. Copy the material ID from the URL in the address bar once you click on the material.
   <br></br>
   ![step_2](https://i.imgur.com/FgCSoTs.png)
3. Put the ID in the `polyhaven2gmod` command.
   `python polyhaven2gmod.py concrete_wall_005`
4. Rinse and repeat! You can specify multiple by placing a comma inbetween material IDs and they will be processed concurrently.
