/**
* Name: Loading of GIS data (roads only)
* Description: Minimal GAMA model – display roads from a shapefile
* Tags: gis
*/

model MK_without_ROI

global {
	// --- GIS input ---
	file shape_file_roads <- file("../includes/shoreline_MK_v1.shp");

	// --- World geometry from road extent ---
	geometry shape <- envelope(shape_file_roads);

	// --- Simulation step ---
	float step <- 10 #mn;

	// --- Initialization ---
	init {
		create road from: shape_file_roads;
	}
}

// =====================================================
// Species: road
// =====================================================

species road {
	rgb color <- #black;
	aspect base {
		draw shape color: rnd_color(255);
	}
}

// =====================================================
// Experiment
// =====================================================

experiment road_traffic type: gui {

	parameter "Shapefile for the roads:" var: shape_file_roads category: "GIS";

	output {
		display road_display type: 3d {
			species road aspect: base;
		}
	}
}
