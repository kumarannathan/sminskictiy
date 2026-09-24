-- StoryErrands (data only -- no logic, no services, no requires)
--
-- NPC errands for phase G. Full narrative context, voice notes and the
-- reasoning behind every number: docs/specs/npc-errands/narrative.md.
--
-- Each top-level key is a stable errand id -- saved progress refers to it,
-- so once shipped these keys do not change or get removed, only appended.
--
-- SHAPE
--   npc          display name + role, for UI/notify text
--   place        { kind, district, label } -- how to resolve the real lot
--                (see the narrative doc: "confirm in Studio" note)
--   voice        one line, for whoever writes any line not covered here
--   wait         either the literal string "SharedWait" (use the shared
--                pool below) or an inline array of this NPC's own lines
--   notifyTitle  the phone/notify() title, always CAPS, reused every beat
--   beaconDone   the wayfinding label once an item is found, points you
--                back to the NPC (<=14 chars)
--   epilogue     5+ variants, said forever once the arc is complete
--   beats        ordered list. Each beat:
--                  say      1-2 short lines (<=40 chars each). Beat 1's
--                           say is a pure ask; beats 2..N-1 are thank-you
--                           (for the previous item) + a new ask; the last
--                           beat is thank-you + a closing line, no task.
--                  task     { kind = "find", hint = <fixed flavour text>,
--                             clue = <optional template string, only on
--                             the one "away" beat per arc; fill in with
--                             the real compass()/streetOf()/nearestLandmark()
--                             helpers already in SminskiServer.server.lua,
--                             do not invent a new clue grammar> }
--                  notify   the phone sub-line for this beat (<=40 chars)
--                  beacon   the wayfinding label while searching (<=14
--                           chars, caps)
--                  reward   coins, paid once, on this beat's find only
--                (the closing beat has no task/notify/beacon/reward)

return {

	----------------------------------------------------------------------
	-- shared pools
	----------------------------------------------------------------------

	-- "not yet" lines for the four plain, chatty voices (Nell, Marlow,
	-- Oskar, Fern). Wren's is her own -- see her entry.
	SharedWait = {
		"Not yet? Keep looking.",
		"No luck? It's got to be close.",
		"Still missing. Try again?",
		"Hmm, not there? Try nearby.",
		"Nothing yet. Don't give up!",
	},

	-- completion toast, shown the instant a hidden item is claimed.
	-- {name} is filled in by whoever wires this up.
	FoundToast = {
		"found it! head back to {name}",
		"got it! {name} will be thrilled",
		"there it is -- {name} is waiting",
		"found! don't keep {name} waiting",
		"nice find -- {name} will love this",
	},

	----------------------------------------------------------------------
	-- the cast
	----------------------------------------------------------------------

	nell = {
		npc = "Nell, the Job Center clerk",
		place = { kind = "jobcentre", district = "downtown", label = "the Job Center" },
		voice = "brisk, dry, quietly proud of her board",
		wait = "SharedWait",
		notifyTitle = "NELL NEEDS A HAND",
		beaconDone = "NELL'S DESK",
		epilogue = {
			"Board's tidy today. Rare.",
			"New listings went up this morning.",
			"We're all square. Thank you again.",
			"The whistle hasn't moved once.",
			"Quiet day at the board.",
		},
		beats = {
			{ say = { "The job board is a mess again.", "My stapler walked off. Again." },
			  task = { kind = "find", hint = "on the steps outside" },
			  notify = "at the Job Center \u{00B7} lost her stapler",
			  beacon = "THE STAPLER", reward = 45 },
			{ say = { "You found it! You're a natural.", "Now the OPEN pin has blown off too." },
			  task = { kind = "find", hint = "just outside, chasing the wind" },
			  notify = "at the Job Center \u{00B7} the OPEN pin blew off",
			  beacon = "THE OPEN PIN", reward = 55 },
			{ say = { "The pin's back up. Marvelous.", "Now my whistle's rolled off somewhere." },
			  task = { kind = "find", hint = "somewhere downtown -- listen for it",
			           clue = "{compass} of City Hall" },
			  notify = "at the Job Center \u{00B7} her whistle rolled off",
			  beacon = "THE WHISTLE", reward = 120 },
			{ say = { "My whistle! Music to my ears.", "Best assistant this board's ever had." } },
		},
	},

	marlow = {
		npc = "Marlow, the florist",
		place = { kind = "shop", shop = "flowers", district = "downtown", label = "the flower shop" },
		voice = "warm, chatty, can't stop smelling things",
		wait = "SharedWait",
		notifyTitle = "MARLOW NEEDS A HAND",
		beaconDone = "MARLOW'S SHOP",
		epilogue = {
			"The peonies are extra fresh today.",
			"Market day went beautifully, thanks to you.",
			"Smell anything nice on your way in?",
			"Still keeping better track of my tools.",
			"Come by anytime -- the door's always open.",
		},
		beats = {
			{ say = { "My watering can's gone walking.", "Have you seen it round the shop?" },
			  task = { kind = "find", hint = "behind the flower buckets" },
			  notify = "the florist's watering can walked off",
			  beacon = "THE CAN", reward = 45 },
			{ say = { "Found it! You've got a green thumb.", "Next: my best seed packet blew off." },
			  task = { kind = "find", hint = "just past the front step" },
			  notify = "the florist \u{00B7} a seed packet blew off",
			  beacon = "THE SEEDS", reward = 55 },
			{ say = { "Seeds recovered. Bless the wind.", "Now my lucky trowel's missing too." },
			  task = { kind = "find", hint = "somewhere out there, downtown",
			           clue = "on {street}, near {landmark}" },
			  notify = "the florist \u{00B7} her lucky trowel is missing",
			  beacon = "THE TROWEL", reward = 120 },
			{ say = { "My trowel! You saved market day.", "This bouquet's half yours, really." } },
		},
	},

	wren = {
		npc = "Wren, the bookseller",
		place = { kind = "shop", shop = "books", district = "downtown", label = "the bookshop" },
		voice = "quiet, slightly magical, says less than she knows",
		wait = {
			"Not yet. It will find you.",
			"Patience. Pages wander slowly.",
			"Still hiding? So is the page.",
			"Not found. It's in no hurry.",
			"Quiet. Keep your eyes open.",
		},
		notifyTitle = "WREN NEEDS A HAND",
		beaconDone = "WREN'S SHOP",
		epilogue = {
			"The book is closed now. Good.",
			"Some books know when to stop.",
			"Thank you for finding all of it.",
			"I reread your page, sometimes.",
			"Quiet in here today. I like that.",
		},
		beats = {
			{ say = { "This book keeps losing its pages.", "Odd. It never used to do that." },
			  task = { kind = "find", hint = "tucked under the reading nook bench" },
			  notify = "the bookshop \u{00B7} a page has gone missing",
			  beacon = "A PAGE", reward = 45 },
			{ say = { "Ah. That page was blank before.", "Find the next one -- it just left." },
			  task = { kind = "find", hint = "just past the shop window" },
			  notify = "the bookshop \u{00B7} another page has wandered off",
			  beacon = "A PAGE", reward = 55 },
			{ say = { "This one has your name in it.", "One more. It went further this time." },
			  task = { kind = "find", hint = "it wandered off, somewhere near the Job Center",
			           clue = "{compass} of the Job Center" },
			  notify = "the bookshop \u{00B7} a page went further this time",
			  beacon = "A PAGE", reward = 120 },
			{ say = { "Curious. The pages are finding you.", "One page left. It won't go far now." },
			  task = { kind = "find", hint = "right by the door, waiting" },
			  notify = "the bookshop \u{00B7} one last page, close by",
			  beacon = "THE LAST PAGE", reward = 80 },
			{ say = { "The last page. It's just your name.", "The book was always going to find you." } },
		},
	},

	oskar = {
		npc = "Oskar, the tailor",
		place = { kind = "shop", shop = "tailor", district = "downtown", label = "the tailor's" },
		voice = "fussy, precise, secretly delighted by help",
		wait = "SharedWait",
		notifyTitle = "OSKAR NEEDS A HAND",
		beaconDone = "OSKAR'S SHOP",
		epilogue = {
			"The commission turned out rather well.",
			"Best-dressed Sminski in town, probably.",
			"Still not one pin out of place.",
			"A little tailoring never hurt anyone.",
			"Do come back if you need mending.",
		},
		beats = {
			{ say = { "My tape measure has vanished.", "Cannot fit a stitch without it." },
			  task = { kind = "find", hint = "on the fitting room floor" },
			  notify = "the tailor's \u{00B7} lost his tape measure",
			  beacon = "TAPE MEASURE", reward = 45 },
			{ say = { "Precisely where I left it. Naturally.", "Now I am missing a spool of thread." },
			  task = { kind = "find", hint = "rolled behind the rack" },
			  notify = "the tailor's \u{00B7} a spool of thread rolled off",
			  beacon = "THE THREAD", reward = 55 },
			{ say = { "The right shade too. How lucky.", "One pin box, somewhere out there." },
			  task = { kind = "find", hint = "somewhere downtown",
			           clue = "on {street}, near {landmark}" },
			  notify = "the tailor's \u{00B7} his pin box is missing",
			  beacon = "THE PIN BOX", reward = 120 },
			{ say = { "Every pin accounted for. Superb.", "The commission is finally finished." } },
		},
	},

	fern = {
		npc = "Fern, the pet shop keeper",
		place = { kind = "shop", shop = "pets", district = "downtown", label = "the pet shop" },
		voice = "soft-hearted, easily worried, loves the shy ones",
		wait = "SharedWait",
		notifyTitle = "FERN NEEDS A HAND",
		beaconDone = "FERN'S SHOP",
		epilogue = {
			"All pups present and accounted for.",
			"Peanut hasn't tried the door once.",
			"Thank you for bringing him home.",
			"The pen's calmer these days.",
			"You're good with the shy ones.",
		},
		beats = {
			{ say = { "Biscuit got out again. Oh no.", "He does this before closing time." },
			  task = { kind = "find", hint = "behind the puppy pen" },
			  notify = "the pet shop \u{00B7} Biscuit got loose again",
			  beacon = "BISCUIT", reward = 45 },
			{ say = { "There he is! Sneaky little guy.", "Now Waffle's missing. Different pup, same trick." },
			  task = { kind = "find", hint = "just past the shop door" },
			  notify = "the pet shop \u{00B7} Waffle got out too",
			  beacon = "WAFFLE", reward = 55 },
			{ say = { "Waffle! Bad dog. Sweet dog.", "Peanut's gone further this time, I think." },
			  task = { kind = "find", hint = "somewhere downtown",
			           clue = "{compass} of City Hall" },
			  notify = "the pet shop \u{00B7} Peanut got further than usual",
			  beacon = "PEANUT", reward = 120 },
			{ say = { "Peanut's home! And staying, I hope.", "Maybe he finally likes it here." } },
		},
	},
}
