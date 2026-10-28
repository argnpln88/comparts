import '../domain/product.dart';

// Illustrative local preview listings, never a fallback for a live query.
final sampleProducts = <Product>[
  _part('1', 'Ryzen 5 7600', 'AMD', PartCategory.cpu, 10995, {
    'Socket': 'AM5',
    'Cores / threads': '6 / 12',
    'Integrated graphics': 'Yes',
  }),
  _part('2', 'GeForce RTX 4060', 'MSI', PartCategory.gpu, 18950, {
    'VRAM': '8 GB GDDR6',
    'Interface': 'PCIe 4.0',
    'Recommended PSU': '550 W',
  }),
  _part('3', 'Vengeance DDR5 32 GB', 'Corsair', PartCategory.ram, 6295, {
    'Memory type': 'DDR5',
    'Capacity': '32 GB (2 × 16 GB)',
    'Speed': '6000 MT/s',
  }),
  _part(
    '4',
    'WD Black SN770 1 TB',
    'Western Digital',
    PartCategory.storage,
    4595,
    {
      'Capacity': '1 TB',
      'Interface': 'PCIe 4.0 NVMe',
      'Form factor': 'M.2 2280',
    },
  ),
  _part('5', 'B650M Gaming WiFi', 'Gigabyte', PartCategory.motherboard, 9295, {
    'Socket': 'AM5',
    'Form factor': 'Micro-ATX',
    'Memory type': 'DDR5',
  }),
  _part('6', 'Focus GX 750 W', 'Seasonic', PartCategory.psu, 6495, {
    'Wattage': '750 W',
    'Efficiency': '80 Plus Gold',
    'Modularity': 'Fully modular',
  }),
  _part('7', 'Airflow Mid Tower', 'Corsair', PartCategory.casePart, 4995, {
    'Motherboard': 'ATX / Micro-ATX',
    'GPU clearance': '360 mm',
    'Cooler clearance': '170 mm',
  }),
  _part('8', 'AK400 Tower Cooler', 'DeepCool', PartCategory.cooler, 1495, {
    'Sockets': 'AM4 / AM5 / LGA1700',
    'Height': '155 mm',
    'Fan': '120 mm',
  }),
  _part('9', '24-inch Gaming Monitor', 'AOC', PartCategory.monitor, 8995, {
    'Resolution': '1920 × 1080',
    'Refresh rate': '180 Hz',
    'Panel': 'IPS',
  }),
  _part(
    '10',
    'Mechanical Keyboard TKL',
    'Keychron',
    PartCategory.peripherals,
    4295,
    {'Layout': 'Tenkeyless', 'Connection': 'USB-C', 'Switches': 'Tactile'},
  ),
  _part('11', 'Core i5-12400F', 'Intel', PartCategory.cpu, 6495, {
    'Socket': 'LGA1700',
    'Cores / threads': '6 / 12',
    'Integrated graphics': 'No',
  }),
  _part('12', 'Radeon RX 6600', 'Sapphire', PartCategory.gpu, 9995, {
    'VRAM': '8 GB GDDR6',
    'Recommended PSU': '500 W',
    'Disclosed condition': 'Sample: tested, cosmetic wear',
  }, condition: 'used'),
  _part('13', 'Fury Beast 16 GB', 'Kingston', PartCategory.ram, 2495, {
    'Memory type': 'DDR4',
    'Capacity': '16 GB (2 × 8 GB)',
    'Speed': '3200 MT/s',
  }),
  _part('14', 'Barracuda 2 TB HDD', 'Seagate', PartCategory.storage, 3295, {
    'Capacity': '2 TB',
    'Interface': 'SATA',
    'Form factor': '3.5-inch',
  }),
  _part('15', 'B760M DDR4', 'ASRock', PartCategory.motherboard, 6995, {
    'Socket': 'LGA1700',
    'Form factor': 'Micro-ATX',
    'Memory type': 'DDR4',
  }),
  _part('16', 'MWE Bronze 650 W', 'Cooler Master', PartCategory.psu, 3495, {
    'Wattage': '650 W',
    'Efficiency': '80 Plus Bronze',
    'Modularity': 'Non-modular',
  }),
  _part('17', 'Compact Mesh Case', 'Montech', PartCategory.casePart, 2695, {
    'Motherboard': 'Micro-ATX / Mini-ITX',
    'GPU clearance': '330 mm',
    'Cooler clearance': '161 mm',
  }),
  _part('18', '120 mm PWM Fan', 'Arctic', PartCategory.cooler, 495, {
    'Size': '120 mm',
    'Control': '4-pin PWM',
    'Included': 'One fan',
  }),
  _part('19', '27-inch QHD Display', 'LG', PartCategory.monitor, 11995, {
    'Resolution': '2560 × 1440',
    'Refresh rate': '75 Hz',
    'Panel': 'IPS',
    'Disclosed condition': 'Sample: refurbished, no known defects',
  }, condition: 'refurbished'),
  _part(
    '20',
    'Wireless Gaming Mouse',
    'Logitech',
    PartCategory.peripherals,
    1995,
    {
      'Connection': '2.4 GHz wireless',
      'Sensor': 'Optical',
      'Included': 'Mouse and USB receiver',
    },
  ),
];
Product _part(
  String id,
  String name,
  String brand,
  PartCategory category,
  int pesos,
  Map<String, String> specs, {
  String condition = 'new',
}) => Product(
  id: id,
  name: name,
  brand: brand,
  category: category,
  priceCentavos: pesos * 100,
  seller: [
    'Circuit Supply',
    'Northside Components',
    'Build Lab',
  ][int.parse(id) % 3],
  condition: condition,
  stock: id == '20' ? 0 : 5,
  specs: specs,
  description: 'An illustrative listing for exploring COMPARTS. Specifications and prices are sample data, not an offer for sale. Check a real seller’s complete listing before buying.',
  warranty: 'Preview only. A real listing must include its seller warranty, accessories, defects, and return policy.',
);
