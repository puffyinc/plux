from typing import TypedDict
from PIL import Image

import argparse
import pathlib
import requests
import os
import subprocess

VMT_TEMPLATE = """"VertexLitGeneric"
{{
	"$basetexture"          "{OUTPUT_FOLDER}/{albedo}"
	"$bumpmap"              "{OUTPUT_FOLDER}/{normal}"
	"$bumptransform"        "center .5 .5 scale 1 1 rotate 0 translate 0 0"
	"$basetexturetransform" "center .5 .5 scale 1 1 rotate 0 translate 0 0
}}
"""

POLYHAVEN_API_URL = "https://api.polyhaven.com"

# Used to group the vistrace and polyhaven folder so its more easy to distinguish the materials from the source code.
ROOT_FOLDER = "materials"
OUTPUT_FOLDER = "polyhaven"
TARGET_EXTENSION = "png"
TARGET_RESOLUTION = "2k"

parser = argparse.ArgumentParser()
parser.add_argument("textures", type=str, help="Comma-separated list of texture names from PolyHaven")
args = parser.parse_args()

class TexAssets(TypedDict):
	albedo_url: str
	normal_url: str
	arm_url: str

class AssetPaths(TypedDict):
	albedo_path: pathlib.Path
	normal_path: pathlib.Path
	arm_path: pathlib.Path

def get_texture_assets(texture: str) -> TexAssets:
	endpoint_url = f"{POLYHAVEN_API_URL}/files/{texture}"
	request = requests.get(endpoint_url)
	api_response = request.json()
	
	return {
		"albedo_url": api_response["Diffuse"][TARGET_RESOLUTION][TARGET_EXTENSION]["url"],
		"normal_url": api_response["nor_dx"][TARGET_RESOLUTION][TARGET_EXTENSION]["url"],
		"arm_url":    api_response["arm"][TARGET_RESOLUTION][TARGET_EXTENSION]["url"],
	}

def download_texture_assets(assets: TexAssets) -> AssetPaths:
	def download(asset_url: str, filename: str) -> pathlib.Path:
		file_request = requests.get(asset_url)
		path = pathlib.Path.cwd() / f"{ROOT_FOLDER}/{OUTPUT_FOLDER}/{filename}.{TARGET_EXTENSION}"
		# Create folders if they don't exist.
		path.parent.mkdir(parents=True, exist_ok=True)

		with open(path, "wb") as file:
			file.write(file_request.content)
		
		return path
	
	return {
		"albedo_path": download(assets["albedo_url"], "albedo"),
		"normal_path": download(assets["normal_url"], "normal"),
		"mrao_path":   download(assets["arm_url"], "albedo_mrao")
	}

def convert_to_targa(paths: AssetPaths) -> AssetPaths:
	def convert(path: pathlib.Path, is_arm: bool = False) -> pathlib.Path:
		parent_path = "vistrace/pbr/" if is_arm else f"{OUTPUT_FOLDER}/"
		new_path = pathlib.Path.cwd() / f"{ROOT_FOLDER}/{parent_path}{path.stem}.tga"
		
		# This can create the PBR path fragment if it does not exist.
		new_path.parent.mkdir(parents=True, exist_ok=True)

		with Image.open(path) as img:
			if is_arm:
				for y in range(img.height):
					for x in range(img.width):
						pixel = img.getpixel((x, y))
						# AO R M
						# 0  1 2
						# M R AO
						# 2 1 0
						img.putpixel((x, y), (pixel[2], pixel[1], pixel[0]))
			img.save(new_path)
		return new_path

	return {
		"albedo_path": convert(paths["albedo_path"]),
		"normal_path": convert(paths["normal_path"]),
		"mrao_path":   convert(paths["mrao_path"], True),
	}

def convert_to_vtf(texture: str, paths: AssetPaths) -> AssetPaths:
	def convert(name: str, is_normalmap: bool, is_mrao: bool, path: pathlib.Path) -> pathlib.Path:
		# Guaranteed to exist because convert_to_targa considered the PBR path fragment and created it.
		parent_path = "vistrace/pbr/" if is_mrao else f"{OUTPUT_FOLDER}/"
		# This is not actually given to VTFCmd, this is just an estimate of the output!
		output = pathlib.Path.cwd() / f"{ROOT_FOLDER}/{parent_path}{texture}_{name}.vtf"
		# Had to run in shell because VTFCmd is so old that it doesn't work with the normal array arguments without shell=True.
		subprocess.run(' '.join(["\"bin/VTFCmd.exe\"", "-flag \"normal\"" if is_normalmap else "", "-format \"dxt5\"", f"-prefix {texture}_", f"-file {path}",]), shell=True)

		return output
	
	return {
		"albedo_path": convert("albedo", False, False, paths["albedo_path"]),
		"normal_path": convert("normal", True, False, paths["normal_path"]),
		"mrao_path":   convert("mrao", False, True, paths["mrao_path"])
	}

def create_vmt(texture: str, paths: AssetPaths):
	with open(f"{ROOT_FOLDER}/{OUTPUT_FOLDER}/{texture}.vmt", "w") as vmt:
		vmt.write(VMT_TEMPLATE.format(OUTPUT_FOLDER = OUTPUT_FOLDER, albedo = paths["albedo_path"].stem, normal = paths["normal_path"].stem))

def convert_texture(texture: str):
	assets = get_texture_assets(texture)
	download_paths = download_texture_assets(assets)
	targa_paths = convert_to_targa(download_paths)

	def clean_assets(paths: AssetPaths):
		# Remove the old files that we no longer need.
		for old_path in paths.values():
			os.remove(old_path)
	
	vtf_paths = convert_to_vtf(texture, targa_paths)
	clean_assets(download_paths)
	clean_assets(targa_paths)
	create_vmt(texture, vtf_paths)
		
textures = args.textures.split(",")

for texture in textures:
	convert_texture(texture)