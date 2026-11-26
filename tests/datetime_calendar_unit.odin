package main

import dt "../src/engine/datatypes"
import "core:fmt"

expect :: proc(parts: dt.DateTime_Parts) {
	value, ok := dt.DateTime_From_Universal_Parts(parts)
	assert(ok)
	actual, valid := dt.DateTime_To_Universal_Parts(value)
	assert(valid)
	assert(actual == parts)
}

main :: proc() {
	assert(dt.DateTime_Days_From_Civil(1970, 1, 1) == 0)
	assert(dt.DateTime_Days_From_Civil(1969, 12, 31) == -1)
	assert(dt.DateTime_Days_From_Civil(2000, 1, 1) == 10957)

	cases := []dt.DateTime_Parts {
		dt.DateTime_Parts{Year = 1400, Month = 1, Day = 1},
		dt.DateTime_Parts{Year = 1600, Month = 2, Day = 29, Hour = 23, Minute = 59, Second = 59},
		dt.DateTime_Parts {
			Year = 1969,
			Month = 12,
			Day = 31,
			Hour = 23,
			Minute = 59,
			Second = 59,
			Millisecond = 999,
		},
		dt.DateTime_Parts{Year = 1970, Month = 1, Day = 1},
		dt.DateTime_Parts {
			Year = 2000,
			Month = 2,
			Day = 29,
			Hour = 12,
			Minute = 30,
			Millisecond = 500,
		},
		dt.DateTime_Parts {
			Year = 2024,
			Month = 2,
			Day = 29,
			Hour = 23,
			Minute = 59,
			Second = 58,
			Millisecond = 125,
		},
		dt.DateTime_Parts{Year = 2400, Month = 7, Day = 31, Hour = 14, Minute = 20},
		dt.DateTime_Parts {
			Year = 9999,
			Month = 12,
			Day = 31,
			Hour = 23,
			Minute = 59,
			Second = 59,
			Millisecond = 999,
		},
	}
	for parts in cases {
		expect(parts)
	}

	invalid_date := dt.DateTime_Parts {
		Year  = 2023,
		Month = 2,
		Day   = 29,
	}
	_, invalid_ok := dt.DateTime_From_Universal_Parts(invalid_date)
	assert(!invalid_ok)
	invalid_date = dt.DateTime_Parts {
		Year  = 2024,
		Month = 13,
		Day   = 1,
	}
	_, invalid_ok = dt.DateTime_From_Universal_Parts(invalid_date)
	assert(!invalid_ok)

	rollover, ok := dt.DateTime_From_Universal_Parts(
		dt.DateTime_Parts{Year = 2024, Month = 1, Day = 1, Minute = 90},
	)
	assert(ok)
	normalized, valid := dt.DateTime_To_Universal_Parts(rollover)
	assert(valid)
	assert(normalized.Hour == 1 && normalized.Minute == 30)

	assert(dt.DateTime_FromUnixTimestamp(1.25).UnixTimestampMillis == 1250)
	negative, valid_negative := dt.DateTime_To_Universal_Parts(
		dt.DateTime_FromUnixTimestampMillis(-1),
	)
	assert(valid_negative && negative.Year == 1969 && negative.Month == 12)
	assert(negative.Day == 31 && negative.Hour == 23 && negative.Minute == 59)
	assert(negative.Second == 59 && negative.Millisecond == 999)

	fmt.println("DATETIME_CALENDAR_UNIT_PASSED")
}
