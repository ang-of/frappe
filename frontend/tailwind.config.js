import frappeUIPreset from 'frappe-ui/tailwind'
import { safeAreaPlugin } from './tailwind/safeArea.js'

export default {
	presets: [frappeUIPreset],
	content: [
		'./index.html',
		'./src/**/*.{vue,js,ts,jsx,tsx}',
		'./node_modules/frappe-ui/src/**/*.{vue,js,ts,jsx,tsx}',
		'../node_modules/frappe-ui/src/**/*.{vue,js,ts,jsx,tsx}',
		'./node_modules/frappe-ui/frappe/**/*.{vue,js,ts,jsx,tsx}',
		'../node_modules/frappe-ui/frappe/**/*.{vue,js,ts,jsx,tsx}',
	],
	theme: {
		extend: {
			// ANG brand (styles/brand.css holds the values). `font-sans` has to
			// follow the brand too, or any element that sets it drops back to the
			// system stack.
			fontFamily: {
				sans: ['var(--ang-font)'],
			},
			colors: {
				ang: {
					'plum-dark': 'var(--ang-plum-dark)',
					plum: 'var(--ang-plum)',
					'plum-light': 'var(--ang-plum-light)',
					'pink-dark': 'var(--ang-pink-dark)',
					pink: 'var(--ang-pink)',
					'pink-light': 'var(--ang-pink-light)',
					grey: 'var(--ang-grey)',
					mist: 'var(--ang-mist)',
					'mist-light': 'var(--ang-mist-light)',
				},
			},
			borderRadius: {
				card: 'var(--ang-radius-card)',
			},
			strokeWidth: {
				1.5: '1.5',
			},
			screens: {
				'2xl': '1600px',
				'3xl': '1920px',
			},
		},
	},
	plugins: [safeAreaPlugin],
}
