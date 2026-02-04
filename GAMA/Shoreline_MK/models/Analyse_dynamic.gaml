model MK_period_mean_change_FINAL

global {

	// =====================
	// INPUT
	// =====================
	file shp_shoreline <- file("../includes/Yearly_shorelines.shp");

	geometry shape <- envelope(shp_shoreline);
	float step <- 10 #mn;

	string FIELD_DATE <- "date";

	// =====================
	// PERIOD DEFINITION
	// =====================
	list<int> period_start <- [1990,1995,2000,2005,2010,2015,2020];
	list<int> period_end   <- [1994,1999,2004,2009,2014,2019,2024];

	list<string> period_label <- [
		"1990–1994","1995–1999","2000–2004",
		"2005–2009","2010–2014","2015–2019","2020–2024"
	];

	list<rgb> period_colors <- [
		rgb(31,119,180), rgb(255,127,14), rgb(44,160,44),
		rgb(214,39,40), rgb(148,103,189),
		rgb(140,86,75), rgb(23,190,207)
	];

	// =====================
	// STORAGE
	// =====================
	map<int, list<geometry>> shores_by_period <- [];
	map<int, geometry> mean_shore_by_period <- [];

	float BUFFER_WIDTH <- 20.0;   // meters
	string SEA_DIR <- "+X";       // đổi nếu hướng bờ khác

	// =====================
	// FUNCTIONS
	// =====================
	int to_year(string s) {
		if (s = nil or length(s) < 4) { return -1; }
		return int(copy_between(s, 0, 4));
	}

	int get_period(int y) {
		loop i from: 0 to: length(period_start) - 1 {
			if (y >= period_start[i] and y <= period_end[i]) {
				return i;
			}
		}
		return -1;
	}

	bool moved_toward_sea(geometry g1, geometry g2) {
		point p1 <- location(g1);
		point p2 <- location(g2);

		if (SEA_DIR = "+X") { return p2.x > p1.x; }
		if (SEA_DIR = "-X") { return p2.x < p1.x; }
		if (SEA_DIR = "+Y") { return p2.y > p1.y; }
		if (SEA_DIR = "-Y") { return p2.y < p1.y; }
		return false;
	}

	init {

		// =================================================
		// LOAD RAW SHORELINES
		// =================================================
		create shoreline from: shp_shoreline;

		loop s over: shoreline {
			int y <- to_year(string(get(s, FIELD_DATE)));
			int pid <- get_period(y);

			if (pid != -1) {
				list<geometry> L <- shores_by_period at pid;
				if (L = nil) { L <- []; }
				shores_by_period <- shores_by_period + [pid :: (L + [s.shape])];
			}
		}

		// =================================================
		// MEAN SHORELINE PER PERIOD
		// =================================================
		loop pid from: 0 to: length(period_label) - 1 {

			list<geometry> L <- shores_by_period at pid;

			if (L != nil and length(L) > 0) {

				geometry gmean <- union(L);
				mean_shore_by_period <- mean_shore_by_period + [pid :: gmean];

				create mean_shoreline {
					shape <- gmean;
					pid <- pid;
				}
			}
		}

		// =================================================
		// CHANGE POLYGONS BETWEEN PERIODS
		// =================================================
		loop pid from: 0 to: length(period_label) - 2 {

			geometry g1 <- mean_shore_by_period at pid;
			geometry g2 <- mean_shore_by_period at (pid + 1);

			if (g1 != nil and g2 != nil) {

				geometry p1 <- buffer(g1, BUFFER_WIDTH);
				geometry p2 <- buffer(g2, BUFFER_WIDTH);
				geometry diff <- (p1 + p2) - (p1 intersection p2);

				bool acc <- moved_toward_sea(g1, g2);
				float A <- area(diff);

				create period_change {
					shape <- diff;
					is_accretion <- acc;
					area_m2 <- A;
				}
			}
		}

		// =================================================
		// LEGEND BOX
		// =================================================
		create legend_box number: 1 {
			p0 <- shape.location + {
				0.015 * shape.envelope.width,
				0.30  * shape.envelope.height
			};
		}

		// ---- LINE LEGEND (MEAN SHORELINES) ----
		create legend_item number: length(period_label) {
			label <- period_label at index;
			c <- period_colors at index;
			location <- legend_box[0].p0 + {200, -(index + 1) * 350};
		}

		// ---- POLYGON LEGEND (ACC / ERO) ----
		create legend_patch number: 2 {
			label <- (index = 0 ? "Accretion" : "Erosion");
			fill_c <- (index = 0 ? rgb(150,180,255) : rgb(255,180,180));
			location <- legend_box[0].p0 + {
				200,
				-(length(period_label) + index + 2) * 350
			};
		}
	}
}

// =====================================================
// RAW SHORELINE (NOT DRAWN)
// =====================================================
species shoreline {}

// =====================================================
// MEAN SHORELINE (LINE ONLY – COLORED)
// =====================================================
species mean_shoreline {
	int pid <- -1;

	aspect base {
		draw shape
			border: (period_colors at pid)
			width: 4;
	}
}

// =====================================================
// PERIOD CHANGE POLYGON (LIGHT COLORS)
// =====================================================
species period_change {
	bool is_accretion <- false;
	float area_m2 <- 0.0;

	aspect base {
		draw shape
			color: (is_accretion ? rgb(150,180,255) : rgb(255,180,180))
			border: #black;
	}
}

// =====================================================
// LEGEND BOX
// =====================================================
species legend_box {
	point p0 <- {0,0};

	aspect base {
		point center <- p0 + {2500, -3000};
		draw rectangle(5000, 6000) at: center color: #white border: #black;
		draw "LEGEND" at: (p0 + {200, -300}) color: #black;
	}
}

// =====================================================
// LEGEND ITEM – LINE
// =====================================================
species legend_item {
	string label <- "";
	rgb c <- #black;

	aspect base {
		draw polyline([location, location + {600,0}])
			color: c
			width: 25;
		draw label at: (location + {800,0}) color: #black;
	}
}

// =====================================================
// LEGEND PATCH – POLYGON
// =====================================================
species legend_patch {
	string label <- "";
	rgb fill_c <- #white;

	aspect base {
		draw rectangle(600, 300)
			at: (location + {300, -150})
			color: fill_c
			border: #black;
		draw label at: (location + {800, -150}) color: #black;
	}
}

// =====================================================
// EXPERIMENT
// =====================================================
experiment view type: gui {
	output {
		display map type: 3d {
			species period_change aspect: base;
			species mean_shoreline aspect: base;
			species legend_box aspect: base;
			species legend_item aspect: base;
			species legend_patch aspect: base;
		}
	}
}
