/**
* Shoreline colored by DAY (yyyy/mm/dd) from shapefile field "date"
* Legend in 3 columns
*/

model MK_without_ROI

global {
	// =====================
	// INPUT FILES
	// =====================
	file shp_shoreline <- file("../includes/Yearly_shorelines.shp");
	file shp_transects <- file("../includes/transects.shp");

	geometry shape <- envelope(shp_shoreline);
	float step <- 10 #mn;

	// =====================
	// DATE FIELD
	// =====================
	string FIELD_DATE <- "date";

	// =====================
	// COLOR PALETTE
	// =====================
	list<rgb> pal <- [
		rgb(31,119,180), rgb(255,127,14), rgb(44,160,44),  rgb(214,39,40),  rgb(148,103,189),
		rgb(140,86,75),  rgb(227,119,194),rgb(127,127,127),rgb(188,189,34), rgb(23,190,207),
		rgb(57,59,121),  rgb(99,121,57),  rgb(140,109,49), rgb(132,60,57),  rgb(123,65,115)
	];

	map<string, rgb> day2c <- [];
	list<string> days <- [];
	int k <- 0;

	// =====================
	// LEGEND SETTINGS
	// =====================
	int legend_max <- 40;

	// vertical spacing between rows (world units)
	float row_dy <- 630.0;

	// width of ONE column area (not total)
	float col_w <- 3020.0;

	// horizontal distance between columns (>= col_w is safe)
	float col_dx <- 3200.0;

	// padding
	float box_pad_top <- 260.0;
	float box_pad_bot <- 120.0;
	float pad_left <- 250.0;

	// 3 columns
	int legend_cols <- 3;

	// computed
	point legend_p0 <- {0,0};    // top-left anchor
	int legend_n <- 0;
	int legend_rows <- 0;

	// =====================
	// FUNCTIONS
	// =====================
	string to_day(string s) {
		if (s = nil or s = "" or s = "nil") { return ""; }
		return copy_between(s, 0, 10); // yyyy/mm/dd
	}

	rgb color_of_day(string day) {
		if (day = "") { return #black; }
		if (!(day2c contains_key day)) {
			day2c <- day2c + [ day :: (pal at (k mod length(pal))) ];
			days  <- days + [day];
			k <- k + 1;
		}
		return day2c at day;
	}

	// =====================
	// INIT
	// =====================
	init {
		// 1) load shoreline
		create shoreline from: shp_shoreline;

		// 2) assign color by day
		loop s over: shoreline {
			s.raw_date <- string(get(s, FIELD_DATE));
			s.day <- to_day(s.raw_date);
			s.color <- color_of_day(s.day);
		}

		// 3) load transects
		create transect from: shp_transects;

		// 4) legend size
		legend_n <- min(legend_max, length(days));

		// 4b) compute rows for 3 columns
		legend_rows <- int(ceil(legend_n / float(legend_cols)));

		// 5) place legend (top-left anchor in world coords)
		legend_p0 <- {
			shape.location.x + (0.30) * shape.envelope.width,
			shape.location.y + (0.20) * shape.envelope.height
		};

		// 6) create legend agents
		create legend_box number: 1;
		create legend_item number: legend_n;

		// 7) configure legend box
		loop b over: legend_box {
			b.p0 <- legend_p0;
			b.w <- col_w + (legend_cols - 1) * col_dx;  // total width
			b.h <- box_pad_top + row_dy * legend_rows + box_pad_bot;
		}

		// 8) set legend items (fill by columns, row-major inside each column)
		loop li over: legend_item {
			int i <- int(li.index);

			int col <- int(floor(i / float(legend_rows)));
			int row <- i mod legend_rows;

			li.label <- days at i;
			li.c <- day2c at li.label;

			// top-left anchor legend_p0; y goes downward -> negative
			li.location <- legend_p0 + {
				pad_left + col_dx * col,
				- (box_pad_top + row_dy * row)
			};
		}
	}
}

// =====================================================
// SPECIES: shoreline
// =====================================================
species shoreline {
	string raw_date <- "";
	string day <- "";
	rgb color <- #black;

	aspect base {
		draw shape color: color border: color width: 2;
	}
}

// =====================================================
// SPECIES: transect
// =====================================================
species transect {
	rgb color <- rgb(90,90,90);

	aspect base {
		draw shape color: color border: color width: 1;
	}
}

// =====================================================
// LEGEND BOX
// =====================================================
species legend_box {
	point p0 <- {0,0};        // top-left anchor
	float w <- 1900.0;
	float h <- 3500.0;

	aspect base {
		point center <- p0 + {w/2, -h/2};
		draw rectangle(w, h) at: center color: #white border: #black;

		// title near top-left inside box
		draw "LEGEND" at: (p0 + {pad_left, -6300}) color: #black;
	}
}

// =====================================================
// LEGEND ITEM
// =====================================================
species legend_item {
	string label <- "";
	rgb c <- #black;

	aspect base {
		// line sample
		draw polyline([
			location + {0, 0},
			location + {600, 0}
		]) color: c width: 20;

		// label text
		draw label at: (location + {800, 0}) color: #black;
	}
}

// =====================================================
// EXPERIMENT
// =====================================================
experiment view type: gui {
	output {
		display map type: 3d {
			species shoreline  aspect: base;
			species transect   aspect: base;
			species legend_box aspect: base;
			species legend_item aspect: base;
		}
	}
}
